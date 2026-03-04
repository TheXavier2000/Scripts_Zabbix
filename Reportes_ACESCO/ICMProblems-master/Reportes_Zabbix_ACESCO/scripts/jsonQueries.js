$(document).ready(function () {
    // Objeto global para almacenar hostids por grupo
    window.groupHosts = {};

    // Token de autenticación (puedes actualizarlo con login automático si lo necesitas)
    const ZABBIX_AUTH = sessionStorage.getItem("zabbixToken");

    // Función para cargar y seleccionar grupos desde la API de Zabbix
    function fetchGroups() {
        fetch('http://10.1.0.66/zabbix/api_jsonrpc.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                jsonrpc: "2.0",
                method: "hostgroup.get",
                params: {
                    output: ["groupid", "name"]
                },
                auth: ZABBIX_AUTH,
                id: 1
            })
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            if (data.error) {
                throw new Error(`Zabbix API Error: ${data.error.message} - ${data.error.data}`);
            }
            const groups = data.result;

            // Autocompletado para grupos
            $("#group-search").autocomplete({
                source: groups.map(group => ({
                    label: group.name,
                    value: group.groupid
                })),
                select: function (event, ui) {
                    const selectedGroupId = ui.item.value;
                    const selectedGroupName = ui.item.label;

                    // Evitar duplicados
                    if ($(`#selected-groups .group[data-id='${selectedGroupId}']`).length === 0) {
                        $("#selected-groups").append(
                            `<div class="group" data-id="${selectedGroupId}">
                                ${selectedGroupName} <span class="remove-group" onclick="removeGroup('${selectedGroupId}')">X</span>
                            </div>`
                        );
                        $("#group-search").val("");

                        // Obtener los hostids del grupo seleccionado
                        fetchHostIdsForGroup(selectedGroupId);
                    }

                    updateSelectedGroupMessage();
                    $("#group-search").autocomplete("close");
                    return false;
                }
            });
        })
        .catch(error => console.error('Error al cargar grupos:', error));
    }

    // Llamar a la función para cargar los grupos al cargar la página
    fetchGroups();

    // Función para actualizar el mensaje con los grupos seleccionados
    function updateSelectedGroupMessage() {
        const groupText = $("#selected-groups .group").map(function () {
            return $(this).text().trim();
        }).get().join(", ");
        $("#selected-group-message").text("Grupos seleccionados: " + groupText);
    }

    // Función global para eliminar un grupo
    window.removeGroup = function (groupId) {
        $(`#selected-groups .group[data-id='${groupId}']`).remove();
        delete window.groupHosts[groupId];
        updateSelectedGroupMessage();
    };

    // Función para obtener los hostids de un grupo
    function fetchHostIdsForGroup(groupId) {
        fetch('http://10.1.0.66/zabbix/api_jsonrpc.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                jsonrpc: "2.0",
                method: "host.get",
                params: {
                    groupids: [groupId],
                    output: ["hostid", "name"]
                },
                auth: ZABBIX_AUTH,
                id: 2
            })
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            if (data.error) {
                throw new Error(`Zabbix API Error: ${data.error.message} - ${data.error.data}`);
            }
            const hosts = data.result;
            window.groupHosts[groupId] = hosts.map(host => host.hostid);
            // Aquí puedes usar window.groupHosts[groupId] según lo necesites
        })
        .catch(error => console.error(`Error al obtener hosts para el grupo ${groupId}:`, error));
    }
});
