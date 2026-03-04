import { createSNMPv2Host } from '../api.js';

export async function addSNMPv2Host(formData) {

  try {

    const result = await createSNMPv2Host({
      host: formData.host,
      ip: formData.ip,
      community: formData.community,
      groupid: formData.groupid,
      templates: formData.templates
    });

    alert("Host SNMPv2 creado correctamente ✅");

    return result;

  } catch (error) {

    console.error("Error creando SNMPv2:", error);
    alert("Error al crear el host SNMPv2 ❌");

  }
}