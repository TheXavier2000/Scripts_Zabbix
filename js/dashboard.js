import { getGroups, getTemplates } from './api.js';

import { logout, getToken } from './auth.js';
import { addICMPHost } from './operations/addICMPHost.js';
import { addSNMPv2Host } from './operations/addSNMPv2Host.js';
import { addSNMPv3Host } from './operations/addSNMPv3Host.js';

if (!getToken()) {
  window.location.href = "login.html";
}

let hosts = [];
let selectedOperation = null;
let selectedGroupId = null;
let selectedTemplateId = null;

let allGroups = [];
let allTemplates = [];

const logContainer = document.getElementById("logContainer");
const hostTable = document.getElementById("hostTable");

const groupList = document.getElementById("groupList");
const templateList = document.getElementById("templateList");

function addLog(msg, type="light") {
  const div = document.createElement("div");
  div.className = `text-${type}`;
  div.innerText = msg;
  logContainer.appendChild(div);
  logContainer.scrollTop = logContainer.scrollHeight;
}

function renderHosts() {
  hostTable.innerHTML = "";
  hosts.forEach(h => {
    hostTable.innerHTML += `
      <tr>
        <td>${h.hostname}</td>
        <td>${h.ip}</td>
        <td>
          <span class="badge bg-${
            h.status === "ok" ? "success" :
            h.status === "error" ? "danger" :
            h.status === "processing" ? "warning" : "secondary"
          }">
            ${h.status}
          </span>
        </td>
      </tr>
    `;
  });
}

/* =============================
   BOTONES DE OPERACIÓN ACTIVOS
============================= */

document.querySelectorAll("[data-op]").forEach(btn => {
  btn.onclick = () => {

    document.querySelectorAll("[data-op]").forEach(b => {
      b.classList.remove("btn-primary","active");
      b.classList.add("btn-outline-light");
    });

    btn.classList.remove("btn-outline-light");
    btn.classList.add("btn-primary","active");

    selectedOperation = btn.dataset.op;
    addLog("Operación seleccionada: " + selectedOperation, "info");
  };
});

/* =============================
   CARGAR GRUPOS
============================= */

async function loadGroups() {
  try {

    const groups = await getGroups();   // 🔥 ahora usamos la función directa

    console.log("Groups response:", groups);

    if (Array.isArray(groups)) {
      allGroups = groups;
      renderGroupList(allGroups);
    } else {
      console.error("Error cargando grupos:", groups);
      allGroups = [];
    }

  } catch (error) {
    console.error("Error en loadGroups:", error);
    allGroups = [];
  }
}

function renderGroupList(groups = []) {

  groupList.innerHTML = "";

  if (!Array.isArray(groups)) return;

  groups.forEach(g => {

    const item = document.createElement("a");
    item.className = "list-group-item list-group-item-action";
    item.innerText = g.name;

    item.onclick = () => {

      document.querySelectorAll("#groupList .list-group-item")
        .forEach(i => i.classList.remove("active"));

      item.classList.add("active");
      selectedGroupId = g.groupid;

      addLog("Grupo seleccionado: " + g.name, "info");
    };

    groupList.appendChild(item);
  });
}


/* =============================
   FILTRO GRUPOS
============================= */

document.getElementById("groupSearch").addEventListener("input", e => {

  const value = e.target.value.toLowerCase();

  const filtered = (allGroups || []).filter(g =>
    g.name.toLowerCase().includes(value)
  );

  renderGroupList(filtered);
});

/* =============================
   CARGAR TEMPLATES
============================= */

async function loadTemplates() {
  try {

    const templates = await getTemplates();  // 🔥 ahora usamos función directa

    console.log("Templates response:", templates);

    if (Array.isArray(templates)) {
      allTemplates = templates;
      renderTemplateList(allTemplates);
    } else {
      console.error("Error cargando templates:", templates);
      allTemplates = [];
    }

  } catch (error) {
    console.error("Error en loadTemplates:", error);
    allTemplates = [];
  }
}

function renderTemplateList(templates = []) {

  templateList.innerHTML = "";

  if (!Array.isArray(templates)) return;

  templates.forEach(t => {

    const item = document.createElement("a");
    item.className = "list-group-item list-group-item-action";
    item.innerText = t.name;

    item.onclick = () => {

      document.querySelectorAll("#templateList .list-group-item")
        .forEach(i => i.classList.remove("active"));

      item.classList.add("active");
      selectedTemplateId = t.templateid;

      addLog("Template seleccionado: " + t.name, "info");
    };

    templateList.appendChild(item);
  });
}


/* =============================
   FILTRO TEMPLATES
============================= */

document.getElementById("templateSearch").addEventListener("input", e => {

  const value = e.target.value.toLowerCase();

  const filtered = (allTemplates || []).filter(t =>
    t.name.toLowerCase().includes(value)
  );

  renderTemplateList(filtered);
});

/* =============================
   EJECUTAR OPERACIÓN
============================= */

document.getElementById("executeBtn").onclick = async () => {

  if (!selectedOperation) return alert("Selecciona una operación");
  if (!selectedGroupId) return alert("Selecciona un grupo");
  if (!selectedTemplateId) return alert("Selecciona un template");
  if (hosts.length === 0) return alert("Agrega al menos un host");

  for (let h of hosts) {
    h.status = "processing";
    renderHosts();

    try {
      const params = { ...h, groupId: selectedGroupId, templateId: selectedTemplateId };

      if (selectedOperation === "icmp") await addICMPHost(params);
      if (selectedOperation === "snmpv2") await addSNMPv2Host(params);
      if (selectedOperation === "snmpv3") await addSNMPv3Host(params);

      h.status = "ok";
      addLog(`${h.hostname} agregado correctamente`, "success");

    } catch (e) {
      h.status = "error";
      addLog(`${h.hostname} error`, "danger");
    }

    renderHosts();
  }
};

document.getElementById("logoutBtn").onclick = logout;

/* =============================
   INICIALIZAR
============================= */

loadGroups();
loadTemplates();