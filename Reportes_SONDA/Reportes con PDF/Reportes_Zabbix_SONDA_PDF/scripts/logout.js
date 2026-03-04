// ===============================
// LOGOUT ZABBIX (logout.js)
// ===============================

function logout() {
    const token = sessionStorage.getItem("zabbixToken");
    const zabbixUrl = "http://10.161.115.127//zabbix/api_jsonrpc.php";

    // Si no hay token, simplemente limpiar y redirigir
    if (!token) {
        sessionStorage.clear();
        window.location.href = "/HTML/login.html";
        return;
    }

    const logoutData = {
        jsonrpc: "2.0",
        method: "user.logout",
        params: [],
        auth: token,
        id: 1
    };

    // Enviamos la solicitud para invalidar el token en Zabbix
    fetch(zabbixUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(logoutData)
    })
    .catch(err => console.error("❌ Error al ejecutar logout:", err))
    .finally(() => {
        // Siempre limpiar el token del navegador
        sessionStorage.clear();

        // Redirigir al login
        window.location.href = "/HTML/login.html";
    });
}
