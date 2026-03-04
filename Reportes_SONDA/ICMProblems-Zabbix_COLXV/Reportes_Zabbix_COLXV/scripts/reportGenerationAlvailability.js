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
        id: 2
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

  async function fetchHostsForGroupWithInventory(groupId) {
    const params = {
      output: ["hostid", "name"],
      groupids: [groupId],
      selectInterfaces: ["ip"],
      selectGroups: ["name"],
      selectInventory: ["type"]  // para Machine Type
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("host.get", params));
  }

  async function fetchPingItemsForHosts(hostIds) {
    const params = {
      output: ["itemid", "hostid", "key_"],
      hostids: hostIds,
      filter: { key_: "icmpping" }
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("item.get", params));
  }

  async function fetchTrendForItems(itemIds, time_from, time_till) {
    const params = {
      output: ["itemid", "clock", "value_avg"],
      itemids: itemIds,
      time_from,
      time_till,
      sortfield: "clock",
      sortorder: "ASC"
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("trend.get", params));
  }

  function unixDayStart(ts) {
    const d = new Date(ts * 1000);
    d.setHours(0, 0, 0, 0);
    return Math.floor(d.getTime() / 1000);
  }

  function unixDayEnd(ts) {
    const d = new Date(ts * 1000);
    d.setHours(23, 59, 59, 999);
    return Math.floor(d.getTime() / 1000);
  }

  $("#generate-report").click(async function () {
    updateStatusMessage("Iniciando generación de informe...");
    $("#generate-report").prop("disabled", true);
    $("#loading-icon").show();
    $("#progress-container").show();

    // Obtener fechas
    let startDate = $("#start-date").val();
    let endDate = $("#end-date").val();

    if (!startDate || !endDate) {
      alert("Selecciona fecha inicio y fin");
      updateStatusMessage("Fechas no seleccionadas", "red");
      $("#generate-report").prop("disabled", false);
      $("#loading-icon").hide();
      $("#progress-container").hide();
      return;
    }

    // Convertir fechas a unix timestamps start of day y end of day
    const timeFrom = unixDayStart(Math.floor(new Date(startDate).getTime() / 1000));
    const timeTill = unixDayEnd(Math.floor(new Date(endDate).getTime() / 1000));

    let selectedGroupIds = $("#selected-groups .group").map(function () {
      return $(this).data("id");
    }).get();
    let selectedGroupNames = $("#selected-groups .group").map(function () {
      return $(this).text().trim().replace(' X', '');
    }).get();

    if (selectedGroupIds.length === 0) {
      alert("Selecciona al menos un grupo");
      updateStatusMessage("No se seleccionó ningún grupo", "red");
      $("#generate-report").prop("disabled", false);
      $("#loading-icon").hide();
      $("#progress-container").hide();
      return;
    }

    // 1. Obtener todos los hosts para todos los grupos
    let hostsPorGrupo = {};
    let allHostIds = [];
    let hostInfoMap = {}; // hostid => info

    for (let i = 0; i < selectedGroupIds.length; i++) {
      const groupId = selectedGroupIds[i];
      const groupName = selectedGroupNames[i];
      const response = await fetchHostsForGroupWithInventory(groupId);
      const hosts = response.result || [];
      hostsPorGrupo[groupName] = hosts;

      for (const host of hosts) {
        allHostIds.push(host.hostid);
        hostInfoMap[host.hostid] = {
          name: host.name,
          ip: (host.interfaces && host.interfaces[0]) ? host.interfaces[0].ip : "Desconocida",
          machineType: (host.inventory && host.inventory.type) ? host.inventory.type : "Desconocido",
          grupo: groupName
        };
      }
    }

    if (allHostIds.length === 0) {
      updateStatusMessage("No hay hosts en los grupos seleccionados", "red");
      $("#generate-report").prop("disabled", false);
      $("#loading-icon").hide();
      $("#progress-container").hide();
      return;
    }

    // 2. Obtener todos los items icmpping de todos los hosts juntos
    updateStatusMessage(`Obteniendo items ping para ${allHostIds.length} hosts...`);
    const pingItemsResp = await fetchPingItemsForHosts(allHostIds);
    const pingItems = pingItemsResp.result || [];

    if (pingItems.length === 0) {
      updateStatusMessage("No hay items de ping para los hosts seleccionados", "red");
      $("#generate-report").prop("disabled", false);
      $("#loading-icon").hide();
      $("#progress-container").hide();
      return;
    }

    // Mapeo itemid => hostid para relacionar después
    const itemIdToHostId = {};
    for (const item of pingItems) {
      itemIdToHostId[item.itemid] = item.hostid;
    }
    const itemIds = pingItems.map(i => i.itemid);

    // 3. Obtener tendencias (trend.get) para todos los items y rango completo
    updateStatusMessage(`Obteniendo tendencias para ${itemIds.length} items...`);
    const trendResp = await fetchTrendForItems(itemIds, timeFrom, timeTill);
    const trends = trendResp.result || [];

    // 4. Procesar tendencias para calcular disponibilidad diaria por host
    let availabilityData = {};

    for (const trend of trends) {
      const hostid = itemIdToHostId[trend.itemid];
      if (!hostid) continue;

      if (!availabilityData[hostid]) availabilityData[hostid] = {};

      const date = new Date(trend.clock * 1000).toISOString().slice(0, 10);

      if (!availabilityData[hostid][date]) {
        availabilityData[hostid][date] = { upPoints: 0, totalPoints: 0 };
      }

      availabilityData[hostid][date].totalPoints++;

      if (parseFloat(trend.value_avg) > 0.5) {
        availabilityData[hostid][date].upPoints++;
      }
    }

    // 5. Preparar datos por grupo para Excel
    let resumenGrupo = {};
    let detallePorGrupo = {};

    // Inicializar
    for (const grupo of selectedGroupNames) {
      resumenGrupo[grupo] = { sumaDisponibilidad: 0, cantidadDías: 0 };
      detallePorGrupo[grupo] = [];
    }

    // Hosts sin items ping: agregar fila N/A en detalle
    for (const [grupo, hosts] of Object.entries(hostsPorGrupo)) {
      for (const host of hosts) {
        if (!new Set(Object.values(itemIdToHostId)).has(host.hostid)) {
          detallePorGrupo[grupo].push({
            Timestamp: "-",
            "Node Name": host.name,
            "IP Address": (host.interfaces && host.interfaces[0]) ? host.interfaces[0].ip : "Desconocida",
            "Machine Type": (host.inventory && host.inventory.type) ? host.inventory.type : "Desconocido",
            Availability: "N/A",
            NODO_GENERICO: grupo
          });
        }
      }
    }

    // Hosts con datos calculados
    for (const [hostid, days] of Object.entries(availabilityData)) {
      const info = hostInfoMap[hostid];
      if (!info) continue;

      for (const [date, data] of Object.entries(days)) {
        let availabilityPercent = data.totalPoints > 0 ? (data.upPoints / data.totalPoints) * 100 : 0;
        availabilityPercent = availabilityPercent.toFixed(2);

        detallePorGrupo[info.grupo].push({
          Timestamp: date,
          "Node Name": info.name,
          "IP Address": info.ip,
          "Machine Type": info.machineType,
          Availability: `${availabilityPercent} %`,
          NODO_GENERICO: info.grupo
        });

        resumenGrupo[info.grupo].sumaDisponibilidad += parseFloat(availabilityPercent);
        resumenGrupo[info.grupo].cantidadDías++;
      }
    }

    updateStatusMessage("Generando archivo Excel...");

    let workbook = XLSX.utils.book_new();

    // Por cada grupo, crear hoja con resumen arriba y detalle debajo
    for (const grupo of selectedGroupNames) {
      const resumenData = resumenGrupo[grupo];
      const promedio = resumenData.cantidadDías > 0 ? (resumenData.sumaDisponibilidad / resumenData.cantidadDías) : 0;

      // Crear fila de resumen manualmente
      let resumenArray = [
        ["Grupo", "Disponibilidad Promedio (%)"],
        [grupo, promedio.toFixed(2)],
        [],
        [] // fila vacía para separar resumen del detalle
      ];

      // Convertir arreglo resumen a hoja
      const wsResumen = XLSX.utils.aoa_to_sheet(resumenArray);

      // Convertir detalle a hoja
      const wsDetalle = XLSX.utils.json_to_sheet(detallePorGrupo[grupo]);

      // Combinar hojas: copiar celdas de detalle debajo del resumen
      // Para eso, vamos a calcular el rango inicial para pegar detalle (filas resumenArray.length + 1)
      const startRowDetalle = resumenArray.length + 1; // Excel base 1

      // Iterar celdas detalle y copiarlas con offset en wsResumen
      const rangeDetalle = XLSX.utils.decode_range(wsDetalle['!ref']);
      for (let R = rangeDetalle.s.r; R <= rangeDetalle.e.r; ++R) {
        for (let C = rangeDetalle.s.c; C <= rangeDetalle.e.c; ++C) {
          const cellAddress = { c: C, r: R };
          const cellRef = XLSX.utils.encode_cell(cellAddress);
          const newCellRef = XLSX.utils.encode_cell({ c: C, r: R + resumenArray.length });
          wsResumen[newCellRef] = wsDetalle[cellRef];
        }
      }

      // Actualizar rango hoja
      const rangeResumen = XLSX.utils.decode_range(wsResumen['!ref']);
      wsResumen['!ref'] = XLSX.utils.encode_range({
        s: { c: 0, r: 0 },
        e: { c: rangeDetalle.e.c, r: rangeDetalle.e.r + resumenArray.length }
      });

      XLSX.utils.book_append_sheet(workbook, wsResumen, grupo.substring(0, 30));
    }

    const excelBuffer = XLSX.write(workbook, { bookType: "xlsx", type: "array" });
    let blob = new Blob([excelBuffer], { type: "application/octet-stream" });
    let link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `Disponibilidad_Ping_${Date.now()}.xlsx`;
    link.click();

    updateStatusMessage("Informe generado con éxito", "green");
    $("#loading-icon").hide();
    $("#progress-container").hide();
    $("#generate-report").prop("disabled", false);
  });

});
