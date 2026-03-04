// ===============================
// LOGIN ZABBIX (login.js)
// ===============================

let zabbixAuthToken = null;


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


function login(event) {
    event.preventDefault();

    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value.trim();
    const messageBox = document.getElementById("loginMessage");

    // Limpiar mensajes previos
    messageBox.textContent = "";
    messageBox.style.color = "";

    if (!username || !password) {
        showToast("Por favor ingresa usuario y contraseña.", "warning");
        return;
    }

    const zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php";

    // === Estructura JSON-RPC exacta que quieres usar ===
    const loginData = {
        jsonrpc: "2.0",
        method: "user.login",
        params: {
            username: username,    // ✅ debe ser 'user', no 'username'
            password: password
        },
        id: 1
    };

    // Mostrar mensaje de carga
    showToast("Verificando credenciales...", "info");

    fetch(zabbixUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(loginData)
    })
    .then(response => response.json())
    .then(data => {
        if (data.result) {
            // ✅ Login exitoso
            const token = data.result;
            sessionStorage.setItem("zabbixToken", token);
            sessionStorage.setItem("lastActivity", Date.now()); // Guardar hora de actividad

            showToast("Login exitoso. Redirigiendo...", "success");


            setTimeout(() => {
                window.location.href = "/HTML/index.html";
            }, 1000);
        } else {

            showToast("Usuario o contraseña incorrectos.", "error");
            console.error("Error en login:", data);
        }
    })
    .catch(error => {
        
        showToast("Error al conectar con Zabbix", "error");
        showToast("No se pudo conectar con el servidor", "error");
    });
}
