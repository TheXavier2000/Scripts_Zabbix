// js/dataFetch.js
import { callZabbixAPI } from "./api.js";
import { getToken } from "./auth.js";

export async function fetchGroups() {
  const token = getToken();
  const groups = await callZabbixAPI(token, "hostgroup.get", {output:["groupid","name"], sortfield:"name"});
  return groups.map(g => ({id: g.groupid, name: g.name}));
}

export async function fetchTemplates() {
  const token = getToken();
  const templates = await callZabbixAPI(token, "template.get", {output:["templateid","name"], sortfield:"name"});
  return templates.map(t => ({id: t.templateid, name: t.name}));
}