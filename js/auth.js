const ZABBIX_API_URL = "http://10.161.115.127/zabbix/api_jsonrpc.php";

let token = localStorage.getItem("zabbixToken");

export function getToken() {
  return token;
}

export function logout() {
  localStorage.removeItem("zabbixToken");
  window.location.href = "index.html";
}

async function login(username, password) {
  const response = await axios.post(ZABBIX_API_URL, {
    jsonrpc: "2.0",
    method: "user.login",
    params: {
      username: username,
      password: password
    },
    id: 1
  });

  if (response.data.result) {
    token = response.data.result;
    localStorage.setItem("zabbixToken", token);
    window.location.href = "index.html";
  } else {
    throw new Error("Login inválido");
  }
}

if (document.getElementById("loginBtn")) {
  document.getElementById("loginBtn").addEventListener("click", async () => {
    const username = document.getElementById("username").value;
    const password = document.getElementById("password").value;

    try {
      await login(username, password);
    } catch (e) {
      document.getElementById("errorMsg").innerText = "Credenciales incorrectas";
    }
  });
}