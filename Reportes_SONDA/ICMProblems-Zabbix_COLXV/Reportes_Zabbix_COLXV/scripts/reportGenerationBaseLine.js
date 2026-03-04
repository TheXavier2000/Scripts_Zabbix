$(document).ready(function () {
  function updateStatusMessage(message, color = "black") {
    console.log(message);
    $("#status-message").text(message).css("color", color);
  }

  const zabbixUrl = 'http://10.161.115.127/zabbix/api_jsonrpc.php';
  const ZABBIX_AUTH = 'c72cf6e672eb4c4800c004902e70f798';

  function getZabbixRequestOptions(method, params) {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'authorization': 'Bearer ' + ZABBIX_AUTH },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: 1
      })
    };
  }

  async function fetchWithRetry(url, options, retries = 3, delay = 1000) {
    try {
      let response = await fetch(url, options);
      if (!response.ok) throw new Error(`HTTP error! Status: ${response.status}`);
      return await response.json();
    } catch (error) {
      if (retries > 0) {
        updateStatusMessage(`Reintentando por error: ${error.message}`, "black");
        await new Promise(resolve => setTimeout(resolve, delay));
        return fetchWithRetry(url, options, retries - 1, delay * 2);
      } else {
        updateStatusMessage(`Falló después de varios intentos: ${error.message}`, "red");
        throw error;
      }
    }
  }

  async function fetchHostsForGroup(groupId) {
    const params = {
      output: ["hostid", "name"],
      groupids: [groupId],
      selectInterfaces: ["ip", "type", "useip"],
      selectTags: "extend"
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("host.get", params));
  }

  function getHostTagValue(tags, key) {
    const tag = tags.find(t => t.tag === key);
    return tag ? tag.value : "";
  }

  function getInterfaceType(interfaces) {
    if (!interfaces || interfaces.length === 0) return "Desconocido";
    const mainInterface = interfaces[0];
    switch (mainInterface.type) {
      case "1": return "ICMP";
      case "2": return "SNMP";
      case "3": return "IPMI";
      case "4": return "JMX";
    }
  }

  function sanitizeSheetName(name) {
    return name.replace(/[\/\\\*\[\]:\?]/g, '|');
  }

  // NUEVA: función para obtener iniciales sanitizadas de un nombre
  function getGroupInitials(name) {
    const clean = name.replace(/[^a-zA-Z0-9]/g, ""); // Elimina caracteres especiales
    return clean.substring(0, 2).toUpperCase(); // Toma las 2 primeras letras en mayúsculas
  }

  $("#generate-report").click(async function () {
    $("#status-message").text("").css("color", "black");

    let selectedGroupIds = $("#selected-groups .group").map(function () {
      return $(this).data("id");
    }).get();
    let selectedGroupNames = $("#selected-groups .group").map(function () {
      return $(this).text().trim().replace(' X', '');
    }).get();

    const startDate = $("#start-date").val();
    const endDate = $("#end-date").val();

    if (selectedGroupIds.length === 0 || !startDate || !endDate) {
      alert("Selecciona al menos un grupo y un rango de fechas.");
      return;
    }

    updateStatusMessage("Iniciando generación del informe");
    $("#generate-report").prop("disabled", true);
    $("#loading-icon").show();
    $("#progress-container").show();

    let workbook = XLSX.utils.book_new();

    for (let i = 0; i < selectedGroupIds.length; i++) {
      const groupId = selectedGroupIds[i];
      const groupName = selectedGroupNames[i];

      updateStatusMessage(`Consultando equipos del grupo ${groupName} (${i + 1}/${selectedGroupIds.length})`);

      const hostResponse = await fetchHostsForGroup(groupId);
      if (!hostResponse || hostResponse.error || !hostResponse.result) {
        updateStatusMessage(`Error al obtener hosts para el grupo ${groupName}`, "red");
        continue;
      }

      const data = hostResponse.result.map(host => {
        return {
          "IP": host.interfaces[0]?.ip || "Desconocida",
          "Polling Method	": getInterfaceType(host.interfaces),
          "Node Name": host.name,
          "Comunidad SNMP": "",
          "GRUPO": getHostTagValue(host.tags, "Grupo_Responsable_2"),
          "ROL": getHostTagValue(host.tags, "Rol"),
          "NODO_GENERICO": getHostTagValue(host.tags, "NODO_GENERICO"),
          "SEDE": getHostTagValue(host.tags, "Sede"),
          "SOLUCION": getHostTagValue(host.tags, "Solucion"),
          "CPU WARNING VALUE": 82,
          "CPU CRITICAL VALUE": 92,
          "MEMORY WARNING VALUE": 82,
          "MEMORY CRITICAL VALUE": 92
        };
      });

      if (data.length > 0) {
        const worksheet = XLSX.utils.json_to_sheet(data, { origin: "A3" });
        const rangeText = `Rango de fechas: ${startDate} al ${endDate}`;
        XLSX.utils.sheet_add_aoa(worksheet, [[rangeText]], { origin: "A1" });

        XLSX.utils.book_append_sheet(workbook, worksheet, sanitizeSheetName(groupName));
      }

      let percentage = Math.round(((i + 1) / selectedGroupIds.length) * 100);
      $("#progress-bar").attr("value", percentage);
      $("#progress-percentage").text(`${percentage}%`);
    }

    // 💡 Construir nombre de archivo con lógica de iniciales si hay más de 3 grupos
    let cleanGroupNames = "";
    if (selectedGroupNames.length > 3) {
      cleanGroupNames = selectedGroupNames.map(getGroupInitials).join("_");
    } else {
      cleanGroupNames = selectedGroupNames
        .map(name => name.replace(/[^a-zA-Z0-9_-]/g, ""))
        .join("_");
    }

    // 💡 Controlar longitud máxima del nombre de archivo
    const filePrefix = `LineaBase_Equipos_`;
    const fileSuffix = `_${startDate}_a_${endDate}.xlsx`;
    const maxFilenameLength = 200;
    const maxGroupNameLength = maxFilenameLength - filePrefix.length - fileSuffix.length;

    if (cleanGroupNames.length > maxGroupNameLength) {
      cleanGroupNames = cleanGroupNames.substring(0, maxGroupNameLength) + "_etc";
    }

    const fileName = `${filePrefix}${cleanGroupNames}${fileSuffix}`;

    const excelBuffer = XLSX.write(workbook, { bookType: "xlsx", type: "array" });
    let blob = new Blob([excelBuffer], { type: "application/octet-stream" });
    let link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = fileName;
    link.click();

    updateStatusMessage("Informe generado con éxito", "green");
    $("#loading-icon").hide();
    $("#progress-container").hide();
    $("#generate-report").prop("disabled", false);
  });
});
