import { createICMPHost } from '../api.js';

export async function addICMPHost(formData) {

  try {

    const result = await createICMPHost({
      host: formData.host,
      ip: formData.ip,
      groupid: formData.groupid,
      templates: formData.templates
    });

    alert("Host creado correctamente ✅");

    return result;

  } catch (error) {

    console.error("Error creando host:", error);
    alert("Error al crear el host ❌");

  }
}