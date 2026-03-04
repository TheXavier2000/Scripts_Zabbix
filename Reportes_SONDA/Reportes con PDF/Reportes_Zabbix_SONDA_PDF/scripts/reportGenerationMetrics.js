$(document).ready(function () {

  function updateStatusMessage(message, color = "black") {
    console.log(message);
    $("#status-message").text(message).css("color", color);
  }

  const zabbixUrl = 'http://10.161.115.127//zabbix/api_jsonrpc.php';
  const bearerToken = sessionStorage.getItem("zabbixToken");

  function getZabbixRequestOptions(method, params) {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: method,
        params: params,
        auth: bearerToken,
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
      selectInterfaces: ["ip"]
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("host.get", params))
      .catch(error => {
        updateStatusMessage(`Error al consultar hosts para el grupo ${groupId}: ${error.message}`, "red");
        return { error: true, groupId: groupId };
      });
  }

  async function fetchMetricItemsForHost(hostId, metricKeys) {
    const params = {
      output: ["itemid", "name", "key_", "units", "lastvalue", "value_type"],
      hostids: hostId,
      sortfield: "name"
    };

    const response = await fetchWithRetry(zabbixUrl, getZabbixRequestOptions("item.get", params));

    if (response.error || !response.result) {
      console.warn(`No se pudo obtener métricas para host ${hostId}`);
      return [];
    }

    // Filtrar solo las métricas que interesan
    return response.result.filter(item =>
      metricKeys.some(key => item.key_.includes(key))
    );
  }

  function convertToUnixTimestamp(dateString, isEndDate = false) {
    let date = new Date(dateString + "T00:00:00-05:00");
    if (isEndDate) date.setHours(23, 59, 59, 999);
    else date.setHours(0, 0, 0, 0);
    return Math.floor(date.getTime() / 1000);
  }

  function sanitizeSheetName(name) {
    return name.replace(/[\/\\\*\[\]:\?]/g, '|');
  }

$("#generate-report").click(async function () {
  $("#status-message").text("").css("color", "black");

  const startDate = $("#start-date").val();
  const endDate = $("#end-date").val();
  const selectedGroupIds = $("#selected-groups .group").map(function () {
    return $(this).data("id");
  }).get();
  const selectedGroupNames = $("#selected-groups .group").map(function () {
    return $(this).text().trim().replace(' X', '');
  }).get();

  const metricKeys = [
    "icmpping",
    "system.cpu.util",
    "vm.memory.size",
    "vm.memory.used",
    "vfs.fs.pused"
  ];

  if (!startDate || !endDate || selectedGroupIds.length === 0) {
    alert("Es necesario llenar todos los campos: fechas y grupos.");
    return;
  }

  updateStatusMessage("Iniciando generación del informe de métricas...");
  $("#generate-report").prop("disabled", true);
  $("#loading-icon").show();
  $("#progress-container").show();

  const startTimestamp = convertToUnixTimestamp(startDate);
  const endTimestamp = convertToUnixTimestamp(endDate, true);

  const groupedData = {};

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  for (let i = 0; i < selectedGroupIds.length; i++) {
    updateStatusMessage(`Procesando métricas para grupo ${selectedGroupNames[i]} (${i + 1}/${selectedGroupIds.length})`);
    $("#progress-bar").attr("value", Math.round(((i) / selectedGroupIds.length) * 90));
    $("#progress-percentage").text(`${Math.round(((i) / selectedGroupIds.length) * 90)}%`);
    await sleep(50);

    const groupId = selectedGroupIds[i];
    const groupName = selectedGroupNames[i];
    const hostResponse = await fetchHostsForGroup(groupId);
    const hosts = hostResponse?.result || [];

    if (hosts.length === 0) {
      updateStatusMessage(`No se encontraron hosts en el grupo ${groupName}`, "orange");
      groupedData[groupName] = [];
      continue;
    }


  function formatMetricValue(value, units) {
  if (value === "N/A" || value === null || value === undefined) return "N/A";

  const num = parseFloat(value);
  if (isNaN(num)) return "N/A";

  // Formatear según unidad
  switch (units) {
    case "B":
    case "Bytes":
      // Convertir a MB o GB si es muy grande
      if (num >= 1e9) return (num / 1e9).toFixed(2) + " GB";
      if (num >= 1e6) return (num / 1e6).toFixed(2) + " MB";
      if (num >= 1e3) return (num / 1e3).toFixed(2) + " KB";
      return num.toFixed(0) + " B";

    case "%":
      return num.toFixed(1) + " %";

    case "s":
    case "sec":
      return num.toFixed(2) + " s";

    default:
      // Para otras unidades, solo un decimal
      return num.toFixed(2) + (units ? ` ${units}` : "");
  }
}


    const reportData = [];

    for (const [index, host] of hosts.entries()) {
      updateStatusMessage(`Procesando host ${host.name} en grupo ${groupName} (${index + 1}/${hosts.length})`);

      const ip = host.interfaces?.[0]?.ip || "N/A";

      const metricItems = await fetchMetricItemsForHost(host.hostid, metricKeys);

      const metricData = {};

      for (const item of metricItems) {
        metricData[item.key_] = {
          name: item.name,
          units: item.units,
          value: item.lastvalue || "0"
        };
        console.log(`Host: ${host.name}, Métrica: ${item.key_}, Valor: ${item.lastvalue}`);
      }

      // Función para sumar valores de métricas que empiecen con cierta raíz
      function sumMetricValues(prefix) {
        const keys = Object.keys(metricData).filter(k => k.startsWith(prefix));
        if (keys.length === 0) return 0;
        return keys.reduce((acc, k) => acc + parseFloat(metricData[k].value) || 0, 0);
      }


      reportData.push({
        "Host": host.name,
        "IP": ip,
        "Ping (último)": formatMetricValue(metricData["icmpping"]?.value, metricData["icmpping"]?.units),
        "CPU utilización (%)": formatMetricValue(sumMetricValues("system.cpu.util"), "%"),
        "Memoria total": formatMetricValue(sumMetricValues("vm.memory.size"), "B"),
        "Memoria usada": formatMetricValue(sumMetricValues("vm.memory.used"), "B"),
        "Disco usado (%)": formatMetricValue(sumMetricValues("vfs.fs.pused"), "%")
      });


      await sleep(10); // Pequeña pausa para refrescar la UI
    }

    groupedData[groupName] = reportData;

    let percentage = Math.round(((i + 1) / selectedGroupIds.length) * 90);
    $("#progress-bar").attr("value", percentage);
    $("#progress-percentage").text(`${percentage}%`);
  }

  updateStatusMessage("Generando archivo Excel...");
  $("#progress-bar").attr("value", 90);
  $("#progress-percentage").text("90%");

  const allEntries = Object.values(groupedData).flat();
  if (allEntries.length === 0) {
    updateStatusMessage("No se encontraron datos para exportar.", "red");
    $("#loading-icon").hide();
    $("#progress-container").hide();
    $("#generate-report").prop("disabled", false);
    return;
  }

  const workbook = XLSX.utils.book_new();
  for (const [groupName, data] of Object.entries(groupedData)) {
    if (data.length === 0) continue;
    const sheet = XLSX.utils.json_to_sheet(data);
    XLSX.utils.book_append_sheet(workbook, sheet, sanitizeSheetName(groupName));
  }

  const buffer = XLSX.write(workbook, { bookType: "xlsx", type: "array" });
  const blob = new Blob([buffer], { type: "application/octet-stream" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `Disponibilidad_${selectedGroupNames.join('|')}_${startDate}_${endDate}.xlsx`;
  link.click();

  $("#progress-bar").attr("value", 100);
  $("#progress-percentage").text("100%");
  updateStatusMessage("Informe generado con éxito", "green");
  $("#loading-icon").hide();
  $("#progress-container").hide();
  $("#generate-report").prop("disabled", false);
});

});
