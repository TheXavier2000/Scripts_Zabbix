import Alpine from 'alpinejs';
import { loadToken, logout } from './auth.js';
import { fetchGroups, fetchTemplates } from './dataFetch.js';
import { addICMPHost } from './operations/addICMPHost.js';
import { addSNMPHost } from './operations/addSNMPv2Host.js';

document.addEventListener('alpine:init', () => {
  Alpine.data('dashboardApp', () => ({
    token: loadToken(),
    currentOp: "Agregar ICMP Host",
    myOperations: [
      { label: "Agregar ICMP Host", func: addICMPHost },
      { label: "Agregar SNMP Host", func: addSNMPHost },
      { label: "Operación 3", func: () => console.log("Op3") },
      { label: "Operación 4", func: () => console.log("Op4") },
      { label: "Operación 5", func: () => console.log("Op5") },
      { label: "Operación 6", func: () => console.log("Op6") },
    ],
    hosts: [],
    allGroups: [],
    allTemplates: [],
    selectedGroupId: null,
    selectedTemplateId: null,
    log: '',

    async init() {
      if (!this.token) { alert("No hay token"); return; }
      this.allGroups = await fetchGroups();
      this.allTemplates = await fetchTemplates();
    },

    selectGroup(g) { this.selectedGroupId = g.id; this.groupSearch = g.name; this.groupResults = []; },
    selectTemplate(t) { this.selectedTemplateId = t.id; this.templateSearch = t.name; this.templateResults = []; },

    async executeOperation() {
      const op = this.myOperations.find(o => o.label === this.currentOp);
      if (op && typeof op.func === 'function') {
        await op.func(this.hosts, this.selectedGroupId, this.selectedTemplateId, msg => { this.log += msg + '\n'; });
      }
    },

    logout() { logout(); location.reload(); }
  }));

  Alpine.start(); // Inicializa Alpine después de registrar el componente
});

