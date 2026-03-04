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

  async function fetchHostsForGroup(groupId) {
    const params = {
      output: ["hostid", "name"],
      groupids: [groupId],
      selectInterfaces: ["ip"],
      selectInventory: ["site_state", "site_city"]
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("host.get", params))
      .catch(error => {
        updateStatusMessage(`Error al consultar hosts para el grupo ${groupId}: ${error.message}`, "red");
        return { error: true, groupId: groupId };
      });
  }

  async function fetchEventsForGroupHosts(groupId, hostIds, timeFrom, timeTill) {
    const params = {
      output: ["eventid", "name", "clock", "severity", "r_eventid"],
      groupids: [groupId],
      hostids: hostIds,
      time_from: timeFrom,
      time_till: timeTill,
      severities: [2, 4],
      selectHosts: ["hostid", "name"],
      sortfield: "clock",
      sortorder: "DESC"
    };
    return fetchWithRetry(zabbixUrl, getZabbixRequestOptions("event.get", params));
  }

  async function fetchResolveTimes(eventIds) {
    if (!eventIds || eventIds.length === 0) return {};
    const params = {
      output: ["clock", "eventid"],
      eventids: eventIds
    };
    const response = await fetchWithRetry(zabbixUrl, getZabbixRequestOptions("event.get", params));
    if (response.error || !response.result) throw new Error("Error al obtener los tiempos de restauración.");
    const resolveTimeMap = {};
    response.result.forEach(event => {
      resolveTimeMap[event.eventid] = parseInt(event.clock);
    });
    return resolveTimeMap;
  }

  function mapSeverityToDescription(severityId) {
    const severityMap = {
      4: "Crítico",
      2: "Warning"
    };
    return severityMap[severityId] || "Desconocido";
  }

  function convertToColombianTime(unixTimestamp) {
    return new Date(unixTimestamp * 1000).toLocaleString("es-CO", { timeZone: "America/Bogota" });
  }

  function calculateDuration(startTimestamp, endTimestamp) {
    let durationSeconds = endTimestamp - startTimestamp;
    let minutes = Math.floor(durationSeconds / 60);
    return `${minutes} minutos`;
  }

  function sanitizeSheetName(name) {
    return name.replace(/[\/\\\*\[\]:\?]/g, '|');
  }

  function normalizeText(text) {
    if (!text || typeof text !== 'string') return "";
    return text
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^\w\s]/g, "")
      .trim();
  }
if (window.location.pathname.endsWith("problems.html")) {
  $("#generate-report").click(async function () {
    $("#status-message").text("").css("color", "black");

    let startDate = $("#start-date").val();
    let endDate = $("#end-date").val();
    let selectedGroupIds = $("#selected-groups .group").map(function () {
      return $(this).data("id");
    }).get();
    let selectedGroupNames = $("#selected-groups .group").map(function () {
      return $(this).text().trim().replace(' X', '');
    }).get();
    let selectedProblems = $("#selected-problems .problem").map(function () {
      return $(this).text().trim().replace(' X', '');
    }).get();

    if (!startDate || !endDate || selectedGroupIds.length === 0 || selectedProblems.length === 0) {
      alert("Es necesario llenar todos los campos: fechas, grupos y problemas.");
      return;
    }

    updateStatusMessage("Iniciando generación del informe");
    $("#generate-report").prop("disabled", true);
    $("#loading-icon").show();
    $("#progress-container").show();

    function convertToUnixTimestamp(dateString, isEndDate = false) {
      let date = new Date(dateString + "T00:00:00-05:00");
      if (isEndDate) date.setHours(23, 59, 59, 999);
      else date.setHours(0, 0, 0, 0);
      return Math.floor(date.getTime() / 1000);
    }

    let startTimestamp = convertToUnixTimestamp(startDate);
    let endTimestamp = convertToUnixTimestamp(endDate, true);

    let hostsByGroup = {};
    let totalHosts = 0;
    for (let i = 0; i < selectedGroupIds.length; i++) {
      const groupId = selectedGroupIds[i];
      const groupName = selectedGroupNames[i];
      const hostData = await fetchHostsForGroup(groupId);
      if (hostData.error) {
        updateStatusMessage(`Error al obtener hosts para grupo ${groupName}`, "red");
        hostsByGroup[groupId] = [];
        continue;
      }
      hostsByGroup[groupId] = hostData.result || [];
      totalHosts += (hostData.result || []).length;
    }

    if (totalHosts === 0) {
      updateStatusMessage("No se encontraron hosts en los grupos seleccionados.", "red");
      $("#loading-icon").hide();
      $("#progress-container").hide();
      $("#generate-report").prop("disabled", false);
      return;
    }

    let groupedData = {};

    for (let i = 0; i < selectedGroupIds.length; i++) {
      const groupId = selectedGroupIds[i];
      const groupName = selectedGroupNames[i];
      const hosts = hostsByGroup[groupId];
      const hostIds = hosts.map(h => h.hostid);

      updateStatusMessage(`Consultando eventos para grupo ${groupName} (${i + 1}/${selectedGroupIds.length})`);

      if (hostIds.length === 0) {
        groupedData[groupName] = [];
        continue;
      }

      const evData = await fetchEventsForGroupHosts(groupId, hostIds, startTimestamp, endTimestamp);

      if (evData.error || !evData.result) {
        updateStatusMessage(`Error al consultar eventos para grupo ${groupName}`, "red");
        groupedData[groupName] = [];
        continue;
      }

      const normalizedProblems = selectedProblems.map(normalizeText);

      const filteredEvents = evData.result.filter(evt => {
        const evtNameNorm = normalizeText(evt.name);
        return normalizedProblems.some(problem => 
          evtNameNorm.includes(problem) || problem.includes(evtNameNorm)
        );
      });

      if (filteredEvents.length === 0) {
        console.warn(`No hubo coincidencias para problemas en grupo ${groupName}`);
        console.log("Eventos encontrados:", evData.result.map(e => e.name));
        console.log("Problemas buscados:", selectedProblems);
      }

      const allEvents = filteredEvents.map(evt => {
        const host = evt.hosts && evt.hosts[0];
        let hostInfo = hosts.find(h => h.hostid === (host ? host.hostid : null));

        let matchedProblem = selectedProblems.find(p =>
          normalizeText(evt.name).includes(normalizeText(p)) ||
          normalizeText(p).includes(normalizeText(evt.name))
        ) || "Desconocido";

        return {
          ...evt,
          matchedProblem,
          __hostName: host ? host.name : "Desconocido",
          __hostIP: hostInfo && hostInfo.interfaces && hostInfo.interfaces[0] ? hostInfo.interfaces[0].ip : "Desconocida"
        };
      });

      const recoveryEventIds = allEvents.filter(e => e.r_eventid).map(e => e.r_eventid);
      const resolveTimeMap = await fetchResolveTimes(recoveryEventIds);

      const reportData = allEvents.map(evt => {
        const startTime = parseInt(evt.clock);
        const resolveTime = evt.r_eventid ? resolveTimeMap[evt.r_eventid] : null;
        const duration = resolveTime ? calculateDuration(startTime, resolveTime) : "En curso";
        return {
          "Hora Inicio": convertToColombianTime(startTime),
          "Estado": mapSeverityToDescription(evt.severity),
          "Host": evt.__hostName,
          "IP": evt.__hostIP,
          "Problema": evt.matchedProblem,
          "Evento": evt.name,
          "Hora Restauración": resolveTime ? convertToColombianTime(resolveTime) : "No resuelto",
          "Duración": duration
        };
      });

      groupedData[groupName] = reportData;

      let percentage = Math.round(((i + 1) / selectedGroupIds.length) * 90);
      $("#progress-bar").attr("value", percentage);
      $("#progress-percentage").text(`${percentage}%`);
    }

    updateStatusMessage("Generando archivo Excel...");
    $("#progress-bar").attr("value", 90);
    $("#progress-percentage").text("90%");

    const allEvents = Object.values(groupedData).flat();

    if (allEvents.length === 0) {
      updateStatusMessage("No se encontraron eventos para los grupos seleccionados en el rango de fechas.", "red");
      $("#loading-icon").hide();
      $("#progress-container").hide();
      $("#generate-report").prop("disabled", false);
      return;
    }

    let workbook = XLSX.utils.book_new();
    for (let [groupName, data] of Object.entries(groupedData)) {
      if (!data || data.length === 0) continue;
      let sanitizedGroupName = sanitizeSheetName(groupName);
      let worksheet = XLSX.utils.json_to_sheet(data);
      XLSX.utils.book_append_sheet(workbook, worksheet, sanitizedGroupName);
    }

    const excelBuffer = XLSX.write(workbook, { bookType: "xlsx", type: "array" });
    let blob = new Blob([excelBuffer], { type: "application/octet-stream" });
    let link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `${selectedGroupNames.join('|')}|${startDate}|${endDate}.xlsx`;
    link.click();

    $("#progress-bar").attr("value", 100);
    $("#progress-percentage").text("100%");
    updateStatusMessage("Informe generado con éxito", "green");
    $("#loading-icon").hide();
    $("#progress-container").hide();
    $("#generate-report").prop("disabled", false);
  });
}
});
