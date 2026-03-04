// js/operations.js
import { callZabbixAPI } from "./api.js";
import { getToken } from "./auth.js";

export async function addICMPHost(hosts, groupId, templateId, logCallback) {
  const token = getToken();
  for (const host of hosts) {
    const params = {
      host: host.hostname,
      interfaces: [{type:1, main:1, useip:1, ip:host.ip, dns:"", port:"10050"}],
      groups: [{groupid: groupId}],
      templates: [{templateid: templateId}]
    };

    const existing = await callZabbixAPI(token, "host.get", {
      filter: {host: host.hostname},
      selectInterfaces: "extend",
      selectGroups: "extend",
      selectParentTemplates: "extend"
    });

    try {
      if (existing.length > 0) {
        const hostId = existing[0].hostid;
        await callZabbixAPI(token, "host.update", { hostid: hostId, interfaces: params.interfaces, groups: params.groups, templates: params.templates });
        logCallback(`[OK] Host ${host.hostname} actualizado`);
      } else {
        await callZabbixAPI(token, "host.create", params);
        logCallback(`[OK] Host ${host.hostname} agregado`);
      }
    } catch(err) {
      logCallback(`[ERROR] Host ${host.hostname}: ${err.message}`);
    }
  }
}