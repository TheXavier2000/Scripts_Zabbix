$(document).ready(function () {

  const zabbixUrl = 'http://10.1.0.66/zabbix/api_jsonrpc.php';
  const bearerToken = sessionStorage.getItem("zabbixToken");

//Ventana Emergente
function showToast(message, type = "info") {
    const container = document.getElementById("toast-container");
    if (!container) return;

    const toast = document.createElement("div");
    toast.classList.add("toast", `toast-${type}`);
    toast.textContent = message;

    container.appendChild(toast);

    setTimeout(() => {
        toast.remove();
    }, 10000); // Duración: 10 segundos
}



  function getZabbixRequestOptions(method, params) {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: method,
        params: params,
        auth: bearerToken,
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
        showToast(`Reintentando por error: ${error.message}`, "warning");
        await new Promise(resolve => setTimeout(resolve, delay));
        return fetchWithRetry(url, options, retries - 1, delay * 2);
      } else {
        showToast(`Falló después de varios intentos: ${error.message}`, "error");
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
        showToast(`Error al consultar hosts para el grupo ${groupId}: ${error.message}`, "error");
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

    showToast("Iniciando generación del informe", "info");
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
        showToast(`Error al obtener hosts para grupo ${groupName}`, "error");
        hostsByGroup[groupId] = [];
        continue;
      }
      hostsByGroup[groupId] = hostData.result || [];
      totalHosts += (hostData.result || []).length;
    }

    if (totalHosts === 0) {
      showToast("No se encontraron hosts en los grupos seleccionados.", "error");
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

      showToast(`Consultando eventos para grupo ${groupName} (${i + 1}/${selectedGroupIds.length})`, "info");

      if (hostIds.length === 0) {
          showToast(`⚠️ El grupo "${groupName}" no tiene hosts asociados.`, "warning");
          groupedData[groupName] = [];
          continue;
      }


      const evData = await fetchEventsForGroupHosts(groupId, hostIds, startTimestamp, endTimestamp);

      if (evData.error || !evData.result) {
        showToast(`Error al consultar eventos para grupo ${groupName}`, "error");
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
      
        showToast(`⚠️ No se encontraron datos para el grupo "${groupName}" con los problemas seleccionados.`, "warning");
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

    showToast("Generando archivo Excel...", "info");
    $("#progress-bar").attr("value", 90);
    $("#progress-percentage").text("90%");

    const allEvents = Object.values(groupedData).flat();

    if (allEvents.length === 0) {
      showToast(`⚠️ No se encontraron eventos en el grupo ${groupName}`, "warning");
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

      // === Aplicar formato tipo tabla a cada hoja ===
      const range = XLSX.utils.decode_range(worksheet["!ref"]);
      for (let R = range.s.r; R <= range.e.r; R++) {
        for (let C = range.s.c; C <= range.e.c; C++) {
          const addr = XLSX.utils.encode_cell({ r: R, c: C });
          const cell = worksheet[addr];
          if (!cell) continue;

          // Encabezado
          if (R === range.s.r) {
            styleCell(cell, {
              fill: { fgColor: { rgb: "1F497D" } },
              font: { bold: true, color: { rgb: "FFFFFF" } },
              alignment: { horizontal: "center", vertical: "center" }
            });
          } else {
            // Filas alternadas
            const fillColor = R % 2 === 0 ? "DCE6F1" : "FFFFFF";
            styleCell(cell, { fill: { fgColor: { rgb: fillColor } } });
          }
        }
      }

      // Activar autofiltro
      worksheet["!autofilter"] = { ref: worksheet["!ref"] };

      XLSX.utils.book_append_sheet(workbook, worksheet, sanitizedGroupName);
    }


// === RESUMEN GLOBAL CON FORMATO DE TABLA Y BORDES ===

function styleCell(cell, options = {}) {
  cell.s = {
    fill: options.fill || {},
    font: options.font || {},
    alignment: options.alignment || { vertical: "center", horizontal: "center" },
    border: {
      top: { style: "thin", color: { rgb: "666666" } },
      bottom: { style: "thin", color: { rgb: "666666" } },
      left: { style: "thin", color: { rgb: "666666" } },
      right: { style: "thin", color: { rgb: "666666" } }
    }
  };

  // Bordes externos más gruesos
  if (options.isOuterBorder) {
    cell.s.border = {
      top: { style: "medium", color: { rgb: "000000" } },
      bottom: { style: "medium", color: { rgb: "000000" } },
      left: { style: "medium", color: { rgb: "000000" } },
      right: { style: "medium", color: { rgb: "000000" } }
    };
  }
}


// === Construcción de datos ===
let hostProblemCounts = {};
let problemCounts = {};

allEvents.forEach(evt => {
  const host = evt["Host"] || "Desconocido";
  const problem = evt["Problema"] || "Desconocido";
  const fecha = evt["Hora Inicio"] || "";

  const key = `${host}||${problem}`;
  if (!hostProblemCounts[key]) {
    hostProblemCounts[key] = { host, problem, count: 0, lastDate: fecha };
  }
  hostProblemCounts[key].count++;
  hostProblemCounts[key].lastDate = fecha;

  problemCounts[problem] = (problemCounts[problem] || 0) + 1;
});

let hostTotals = {};
Object.values(hostProblemCounts).forEach(({ host, count }) => {
  hostTotals[host] = (hostTotals[host] || 0) + count;
});

let topHosts = Object.entries(hostTotals)
  .sort((a, b) => b[1] - a[1])
  .slice(0, 10);

let leftTable = topHosts.map(([host, total]) => {
  let problemsForHost = Object.values(hostProblemCounts)
    .filter(p => p.host === host)
    .sort((a, b) => b.count - a.count);

  return {
    "Problema": problemsForHost[0]?.problem || "Desconocido",
    "Equipo": host,
    "Cantidad": total,
    "Fecha": problemsForHost[0]?.lastDate || ""
  };
});

let topHostName = topHosts[0]?.[0] || "N/A";
let topHostProblems = Object.values(hostProblemCounts)
  .filter(p => p.host === topHostName)
  .sort((a, b) => b.count - a.count)
  .slice(0, 10)
  .map(p => ({
    "Equipo con más Problemas": topHostName,
    "Nombre Problema": p.problem,
    "Fecha": p.lastDate,
    "Cantidad": p.count
  }));

// === Crear hoja ===
let resumenSheet = {};
XLSX.utils.sheet_add_aoa(resumenSheet, [["Top 10 Equipos con Más Problemas"]], { origin: "A1" });
XLSX.utils.sheet_add_json(resumenSheet, leftTable, { origin: "A3" });

XLSX.utils.sheet_add_aoa(resumenSheet, [["Problemas del Equipo con Más Incidentes"]], { origin: "G1" });
XLSX.utils.sheet_add_json(resumenSheet, topHostProblems, { origin: "G3" });

resumenSheet["!cols"] = [
  { wch: 35 }, { wch: 30 }, { wch: 12 }, { wch: 20 },
  { wch: 5 }, { wch: 5 },
  { wch: 35 }, { wch: 40 }, { wch: 20 }, { wch: 12 }
];

// === Aplicar estilo visual tipo "tabla de Excel" con bordes ===
function applyTableLook(sheet, startRow, startCol, endRow, endCol) {
  for (let R = startRow; R <= endRow; R++) {
    for (let C = startCol; C <= endCol; C++) {
      const addr = XLSX.utils.encode_cell({ r: R, c: C });
      const cell = sheet[addr];
      if (!cell) continue;

      // Determinar si la celda está en el borde externo
      const isOuter =
        R === startRow || R === endRow || C === startCol || C === endCol;

      // === Encabezado ===
      if (R === startRow) {
        cell.s = {
          fill: { fgColor: { rgb: "1F497D" } }, // azul oscuro
          font: { bold: true, color: { rgb: "FFFFFF" } },
          alignment: { horizontal: "center", vertical: "center" },
          border: {
            top: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            bottom: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            left: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            right: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } }
          }
        };
      } 
      // === Filas alternadas ===
      else {
        const fillColor = R % 2 === 0 ? "DCE6F1" : "FFFFFF";
        cell.s = {
          fill: { fgColor: { rgb: fillColor } },
          alignment: { horizontal: "center", vertical: "center" },
          border: {
            top: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            bottom: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            left: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } },
            right: { style: isOuter ? "medium" : "thin", color: { rgb: "000000" } }
          }
        };
      }
    }
  }
}


// Detectar el rango de las tablas y aplicar formato
const leftRange = XLSX.utils.decode_range(`A3:D${3 + leftTable.length}`);
const rightRange = XLSX.utils.decode_range(`G3:J${3 + topHostProblems.length}`);
applyTableLook(resumenSheet, leftRange.s.r, leftRange.s.c, leftRange.e.r, leftRange.e.c);
applyTableLook(resumenSheet, rightRange.s.r, rightRange.s.c, rightRange.e.r, rightRange.e.c);

// Activar autofiltros (como Ctrl+T)
resumenSheet["!autofilter"] = { ref: `A3:D${3 + leftTable.length}` };
resumenSheet["!autofilter_right"] = { ref: `G3:J${3 + topHostProblems.length}` };

// Agregar hoja al libro
XLSX.utils.book_append_sheet(workbook, resumenSheet, "Resumen Global");






    const excelBuffer = XLSX.write(workbook, { bookType: "xlsx", type: "array" });
    let blob = new Blob([excelBuffer], { type: "application/octet-stream" });
    let link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `${selectedGroupNames.join('|')}|${startDate}|${endDate}.xlsx`;
    link.click();

    $("#progress-bar").attr("value", 100);
    $("#progress-percentage").text("100%");
    showToast("Informe generado con éxito", "success");
    $("#loading-icon").hide();
    $("#progress-container").hide();
    $("#generate-report").prop("disabled", false);
  });





}
});
