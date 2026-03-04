// =============================
// CONFIGURACIÓN
// =============================
const ZABBIX_URL = "http://10.161.115.127/zabbix/api_jsonrpc.php";

let authToken = localStorage.getItem("zabbixToken");


// =============================
// LOGIN
// =============================
export async function login(username, password) {

  const response = await fetch(ZABBIX_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json-rpc"
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "user.login",
      params: {
        username: username,
        password: password
      },
      id: 1
    })
  });

  const data = await response.json();

  if (data.result) {

    authToken = data.result;

    // 🔥 GUARDAR TOKEN
    localStorage.setItem("zabbixToken", authToken);

    return true;
  }

  return false;
}


// =============================
// FUNCIÓN GENÉRICA
// =============================
async function callZabbix(method, params = {}) {

  const response = await fetch(ZABBIX_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json-rpc",
      "Authorization": `Bearer ${authToken}`
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method,
      params,
      id: 1
    })
  });

  const data = await response.json();

  if (data.error) {

    console.error("Zabbix API error:", data);

    // 🔥 Si la sesión expiró
    if (data.error.data?.includes("Session terminated")) {

      localStorage.removeItem("zabbixToken");
      alert("Sesión expirada. Por favor inicie sesión nuevamente.");

      window.location.href = "index.html";
    }

    throw data.error;
  }

  return data.result;
}


// =============================
// GRUPOS
// =============================
export async function getGroups() {
  return await callZabbix("hostgroup.get", {
    output: ["groupid", "name"]
  });
}


// =============================
// TEMPLATES
// =============================
export async function getTemplates() {
  return await callZabbix("template.get", {
    output: ["templateid", "name"],
    selectHosts: "count"
  });
}


// =============================
// CREAR HOST ICMP
// =============================
export async function createICMPHost(hostData) {

  return await callZabbix("host.create", {
    host: hostData.host,
    interfaces: [
      {
        type: 1,
        main: 1,
        useip: 1,
        ip: hostData.ip,
        dns: "",
        port: "10050"
      }
    ],
    groups: [
      {
        groupid: hostData.groupid
      }
    ],
    templates: hostData.templates.map(t => ({
      templateid: t
    }))
  });
}

// =============================
// CREAR HOST SNMPv2
// =============================
export async function createSNMPv2Host(hostData) {

  return await callZabbix("host.create", {
    host: hostData.host,

    interfaces: [
      {
        type: 2,          // SNMP
        main: 1,
        useip: 1,
        ip: hostData.ip,
        dns: "",
        port: "161",
        details: {
          version: 2,
          community: hostData.community,
          bulk: 1
        }
      }
    ],

    groups: [
      {
        groupid: hostData.groupid
      }
    ],

    templates: hostData.templates.map(t => ({
      templateid: t
    }))
  });
}


// =============================
// CREAR HOST SNMPv3
// =============================
export async function createSNMPv3Host(hostData) {

  return await callZabbix("host.create", {
    host: hostData.host,

    interfaces: [
      {
        type: 2,
        main: 1,
        useip: 1,
        ip: hostData.ip,
        dns: "",
        port: "161",
        details: {
          version: 3,
          bulk: 1,
          securityname: hostData.securityname,
          securitylevel: hostData.securitylevel, // 0=noAuthNoPriv, 1=authNoPriv, 2=authPriv
          authprotocol: hostData.authprotocol,   // 0=MD5, 1=SHA
          authpassphrase: hostData.authpassphrase,
          privprotocol: hostData.privprotocol,   // 0=DES, 1=AES
          privpassphrase: hostData.privpassphrase
        }
      }
    ],

    groups: [
      {
        groupid: hostData.groupid
      }
    ],

    templates: hostData.templates.map(t => ({
      templateid: t
    }))
  });
}
