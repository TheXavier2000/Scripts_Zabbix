$(document).ready(function () {

  const zabbixUrl = 'http://10.161.115.127/zabbix/api_jsonrpc.php';
  const bearerToken = sessionStorage.getItem("zabbixToken");

  /* =========================
     UTILIDADES BASE (TU BASE)
     ========================= */

  function showToast(message, type = "info") {
    const container = document.getElementById("toast-container");
    if (!container) return;

    const toast = document.createElement("div");
    toast.classList.add("toast", `toast-${type}`);
    toast.textContent = message;

    container.appendChild(toast);
    setTimeout(() => toast.remove(), 8000);
  }

  function getZabbixRequestOptions(method, params) {
    return {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method,
        params,
        auth: bearerToken,
        id: 1
      })
    };
  }

  async function fetchWithRetry(url, options, retries = 3, delay = 1000) {
    try {
      const response = await fetch(url, options);
      if (!response.ok) throw new Error(response.status);
      return await response.json();
    } catch (err) {
      if (retries > 0) {
        await new Promise(r => setTimeout(r, delay));
        return fetchWithRetry(url, options, retries - 1, delay * 2);
      }
      throw err;
    }
  }

  async function fetchHostsForGroup(groupId) {
    const params = {
      output: ["hostid", "name"],
      groupids: [groupId]
    };
    return fetchWithRetry(
      zabbixUrl,
      getZabbixRequestOptions("host.get", params)
    );
  }

  /* =========================
     HANDLERS DE REPORTES
     ========================= */

  // 🔵 REPORTE CPU
  async function generateCpuReport(groupIds, groupNames, timeFrom, timeTill) {

    const result = {};

    for (let i = 0; i < groupIds.length; i++) {
      const groupId = groupIds[i];
      const groupName = groupNames[i];

      showToast(`Procesando CPU: ${groupName}`, "info");

      const hostsRes = await fetchHostsForGroup(groupId);
      if (!hostsRes.result.length) continue;

      const hostIds = hostsRes.result.map(h => h.hostid);

      // Items CPU
      const itemsRes = await fetchWithRetry(
        zabbixUrl,
        getZabbixRequestOptions("item.get", {
          output: ["itemid"],
          hostids: hostIds,
          search: { key_: "system.cpu.util[,avg1]" }
        })
      );

      if (!itemsRes.result.length) continue;

      const itemIds = itemsRes.result.map(i => i.itemid);

      // Trends
      const trendsRes = await fetchWithRetry(
        zabbixUrl,
        getZabbixRequestOptions("trend.get", {
          output: ["value_avg"],
          itemids: itemIds,
          time_from: timeFrom,
          time_till: timeTill
        })
      );

      if (!trendsRes.result.length) continue;

      const avg =
        trendsRes.result.reduce((s, t) => s + parseFloat(t.value_avg), 0) /
        trendsRes.result.length;

      result[groupName] = Number(avg.toFixed(2));
    }

    return {
      labels: Object.keys(result),
      values: Object.values(result),
      label: "CPU promedio (%)"
    };
  }

  // 🔴 REPORTE EVENTOS (resumen)
  async function generateEventsReport(groupIds, groupNames, timeFrom, timeTill) {

    const result = {};

    for (let i = 0; i < groupIds.length; i++) {
      const groupId = groupIds[i];
      const groupName = groupNames[i];

      showToast(`Procesando eventos: ${groupName}`, "info");

      const hostsRes = await fetchHostsForGroup(groupId);
      if (!hostsRes.result.length) continue;

      const hostIds = hostsRes.result.map(h => h.hostid);

      const eventsRes = await fetchWithRetry(
        zabbixUrl,
        getZabbixRequestOptions("event.get", {
          output: ["eventid"],
          hostids: hostIds,
          time_from: timeFrom,
          time_till: timeTill,
          severities: [2, 3, 4, 5]
        })
      );

      result[groupName] = eventsRes.result.length;
    }

    return {
      labels: Object.keys(result),
      values: Object.values(result),
      label: "Cantidad de eventos"
    };
  }

  /* =========================
     GRÁFICA
     ========================= */

  let chartInstance = null;

  function drawChart(dataset) {
    const ctx = document.getElementById("reportChart");

    if (chartInstance) chartInstance.destroy();

    chartInstance = new Chart(ctx, {
      type: "bar",
      data: {
        labels: dataset.labels,
        datasets: [{
          label: dataset.label,
          data: dataset.values,
          backgroundColor: "#1F497D"
        }]
      },
      options: {
        responsive: true,
        scales: {
          y: { beginAtZero: true }
        }
      }
    });
  }

  /* =========================
     BOTÓN GENERAR REPORTE
     ========================= */

  $("#generate-report").click(async function () {

    const startDate = $("#start-date").val();
    const endDate = $("#end-date").val();
    const reportType = $("#report-type").val();

    const groupIds = $("#selected-groups .group")
      .map(function () { return $(this).data("id"); })
      .get();

    const groupNames = $("#selected-groups .group")
      .map(function () { return $(this).text().replace(" X", "").trim(); })
      .get();

    if (!startDate || !endDate || !groupIds.length) {
      alert("Debe seleccionar fechas y grupos");
      return;
    }

    const toUnix = (d, end = false) => {
      const date = new Date(d + "T00:00:00-05:00");
      if (end) date.setHours(23, 59, 59, 999);
      return Math.floor(date.getTime() / 1000);
    };

    const timeFrom = toUnix(startDate);
    const timeTill = toUnix(endDate, true);

    showToast("Generando reporte...", "info");

    let dataset;

    if (reportType === "cpu") {
      dataset = await generateCpuReport(groupIds, groupNames, timeFrom, timeTill);
    } else if (reportType === "events") {
      dataset = await generateEventsReport(groupIds, groupNames, timeFrom, timeTill);
    } else {
      alert("Tipo de reporte no soportado");
      return;
    }

    drawChart(dataset);
    showToast("Reporte generado correctamente", "success");
  });

});
