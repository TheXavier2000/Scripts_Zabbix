// ===============================
// auth.js  🔒 Manejo de sesión Zabbix
// ===============================

// Tiempo máximo de inactividad (en milisegundos)
const MAX_INACTIVITY_TIME = 10 * 60 * 1000; // 10 minutos

// Verificar login al cargar la página
function requireLogin() {
  const token = sessionStorage.getItem("zabbixToken");
  const lastActivity = sessionStorage.getItem("lastActivity");

  // Si no hay token, redirigir al login
  if (!token) {
    window.location.href = "login.html";
    return;
  }

  // Si ha pasado demasiado tiempo sin actividad → cerrar sesión
  if (lastActivity && Date.now() - parseInt(lastActivity) > MAX_INACTIVITY_TIME) {
    logout("Tu sesión ha expirado por inactividad.");
    return;
  }

  // Actualizar hora de actividad
  updateActivityTimer();

  // Detectar movimiento o clic para resetear el temporizador
  document.addEventListener("mousemove", updateActivityTimer);
  document.addEventListener("keydown", updateActivityTimer);
}

// Actualiza el tiempo de última actividad
function updateActivityTimer() {
  sessionStorage.setItem("lastActivity", Date.now());
}

// Cierra la sesión (por logout manual o inactividad)
function logout(message = "Has cerrado sesión correctamente.") {
  sessionStorage.removeItem("zabbixToken");
  sessionStorage.removeItem("lastActivity");

  alert(message);
  window.location.href = "login.html";
}
