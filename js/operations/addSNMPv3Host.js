import { createSNMPv3Host } from '../api.js';

export async function addSNMPv3Host(formData) {

  try {

    const result = await createSNMPv3Host({
      host: formData.host,
      ip: formData.ip,
      groupid: formData.groupid,
      templates: formData.templates,

      securityname: formData.securityname,
      securitylevel: formData.securitylevel,
      authprotocol: formData.authprotocol,
      authpassphrase: formData.authpassphrase,
      privprotocol: formData.privprotocol,
      privpassphrase: formData.privpassphrase
    });

    alert("Host SNMPv3 creado correctamente ✅");

    return result;

  } catch (error) {

    console.error("Error creando SNMPv3:", error);
    alert("Error al crear el host SNMPv3 ❌");

  }
}