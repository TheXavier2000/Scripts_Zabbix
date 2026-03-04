// auth.js
export let token = null;

// Guardar token en localStorage para persistencia
export function saveToken(t) {
    token = t;
    localStorage.setItem('zabbixToken', t);
}

// Recuperar token al iniciar
export function loadToken() {
    const stored = localStorage.getItem('zabbixToken');
    if (stored) token = stored;
    return token;
}

// Login: enviar usuario y password a Zabbix API
export async function login(username, password, apiUrl) {
    try {
        const payload = {
            jsonrpc: "2.0",
            method: "user.login",
            params: { user: username, password: password },
            id: Date.now(),
            auth: null
        };
        const res = await axios.post(apiUrl, payload);
        if (res.data.result) {
            saveToken(res.data.result);
            return res.data.result;
        } else {
            throw new Error(res.data.error?.data || 'Login fallido');
        }
    } catch (err) {
        console.error("Login error:", err);
        throw err;
    }
}

// Logout: borrar token
export function logout() {
    token = null;
    localStorage.removeItem('zabbixToken');
}