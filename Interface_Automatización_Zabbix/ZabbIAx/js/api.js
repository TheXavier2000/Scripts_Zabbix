// js/api.js
export async function callZabbixAPI(token, method, params) {
  try {
    const payload = { jsonrpc: "2.0", method, params, auth: token, id: Date.now() };
    const res = await axios.post("http://10.161.115.127/zabbix/api_jsonrpc.php", payload);
    return res.data.result || [];
  } catch (err) {
    console.error("Zabbix API error:", err);
    return [];
  }
}