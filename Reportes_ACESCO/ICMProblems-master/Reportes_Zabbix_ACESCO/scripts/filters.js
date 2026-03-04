$(document).ready(function () {
    // Truncar nombres largos
    function truncateName(name, maxLength) {
        return name.length > maxLength ? name.substring(0, maxLength) + '...' : name;
    }

    // Posicionar dropdowns debajo del input
    function adjustDropdownMenuPosition($input, $dropdownMenu) {
        const offset = $input.offset();
        const width = $input.outerWidth();
        const height = $input.outerHeight();

        $dropdownMenu.css({
            top: offset.top + height,
            left: offset.left,
            width: width
        });
    }

    // === Cargar GRUPOS desde Zabbix ===
    function loadGroups() {
        const zabbixUrl = "http://10.1.0.66/zabbix/api_jsonrpc.php";
        const authToken = sessionStorage.getItem("zabbixToken");

        const requestData = {
            jsonrpc: "2.0",
            method: "hostgroup.get",
            params: {
                output: ["groupid", "name"]
            },
            auth: authToken,  // Se agrega el token en el cuerpo

            id: 1
        };

        $.ajax({
            url: zabbixUrl,
            method: "POST",
            contentType: "application/json",
            data: JSON.stringify(requestData),
            success: function (response) {
                if (!response.result || !Array.isArray(response.result)) {
                    console.error("Respuesta inválida desde Zabbix:", response);
                    $("#group-dropdown-menu").html('<div>Error al procesar los datos</div>');
                    return;
                }

                const groups = response.result;

                // Autocompletado
                $("#group-search").autocomplete({
                    source: groups.map(item => ({
                        label: item.name,
                        value: item.groupid
                    })),
                    minLength: 0,
                    open: function () {
                        adjustDropdownMenuPosition($("#group-search"), $("#group-dropdown-menu"));
                        $("#group-dropdown-menu").show();
                    },
                    select: function (event, ui) {
                        const selectedGroupId = ui.item.value;
                        const selectedGroupName = ui.item.label;

                        if ($("#selected-groups .group[data-id='" + selectedGroupId + "']").length === 0) {
                            $("#selected-groups").append(
                                `<div class="group" data-id="${selectedGroupId}">
                                    ${truncateName(selectedGroupName, 25)} <span class="remove-group" onclick="removeGroup('${selectedGroupId}')">X</span>
                                </div>`
                            );
                            $("#group-search").val("");
                        }

                        $("#selected-group-message").text("Grupos seleccionados: " + $("#selected-groups .group").map(function () {
                            return $(this).text().trim();
                        }).get().join(", "));

                        $("#group-dropdown-menu").hide();
                        return false;
                    }
                });

                // Dropdown visible debajo
                const dropdownContent = groups.map(item => (
                    `<div data-id="${item.groupid}">${item.name}</div>`
                )).join('');
                $("#group-dropdown-menu").html(dropdownContent);

                // Selección por clic
                $("#group-dropdown-menu").on('click', 'div', function () {
                    const selectedGroupId = $(this).data('id');
                    const selectedGroupName = $(this).text();

                    if ($("#selected-groups .group[data-id='" + selectedGroupId + "']").length === 0) {
                        $("#selected-groups").append(
                            `<div class="group" data-id="${selectedGroupId}">
                                ${truncateName(selectedGroupName, 25)} <span class="remove-group" onclick="removeGroup('${selectedGroupId}')">X</span>
                            </div>`
                        );
                        $("#group-search").val("");
                    }

                    $("#selected-group-message").text("Grupos seleccionados: " + $("#selected-groups .group").map(function () {
                        return $(this).text().trim();
                    }).get().join(", "));

                    $("#group-dropdown-menu").hide();
                });

            },
            error: function (xhr, status, error) {
                console.error("Error al consultar grupos desde Zabbix API:", status, error);
                $("#group-dropdown-menu").html('<div>Error al cargar grupos</div>');
            }
        });
    }


    // === Cargar PROBLEMAS desde archivo local JSON === 
    function loadProblems() {
        let cacheBuster = new Date().getTime();

        $.getJSON('../json/problems.json?v=' + cacheBuster, function (data) {
            if (!Array.isArray(data)) {
                console.error("El formato de los datos no es un array.");
                $("#problem-dropdown-menu").html('<div>Error al procesar los datos</div>');
                return;
            }

            $.ui.autocomplete.filter = function(array, term) {
                const matcher = new RegExp($.ui.autocomplete.escapeRegex(term), "i");
                return $.grep(array, function(value) {
                    return matcher.test(value.label || value.value || value);
                });
            };

            $("#problem-search").autocomplete({
                source: data.map(item => ({
                    label: item.name,
                    value: item.id
                })),
                minLength: 0,
                open: function () {
                    adjustDropdownMenuPosition($("#problem-search"), $("#problem-dropdown-menu"));
                    $("#problem-dropdown-menu").show();
                },
                select: function (event, ui) {
                    let selectedProblemId = ui.item.value;
                    let selectedProblemName = ui.item.label;

                    if ($("#selected-problems .problem[data-id='" + selectedProblemId + "']").length === 0) {
                        $("#selected-problems").append(
                            `<div class="problem" data-id="${selectedProblemId}">
                                ${truncateName(selectedProblemName, 25)} <span class="remove-problem">X</span>
                            </div>`
                        );
                        $("#problem-search").val("");
                    }

                    $("#selected-problem-message").text("Problemas seleccionados: " + $("#selected-problems .problem").map(function () {
                        return $(this).text().trim();
                    }).get().join(", "));
                    $("#problem-dropdown-menu").hide();
                    return false;
                }
            });

            let dropdownContent = data.map(item => (
                `<div data-id="${item.id}">${item.name}</div>`
            )).join('');
            $("#problem-dropdown-menu").html(dropdownContent);

            $("#problem-dropdown-menu").on('click', 'div', function () {
                let selectedProblemId = $(this).data('id');
                let selectedProblemName = $(this).text();

                if ($("#selected-problems .problem[data-id='" + selectedProblemId + "']").length === 0) {
                    $("#selected-problems").append(
                        `<div class="problem" data-id="${selectedProblemId}">
                            ${truncateName(selectedProblemName, 25)} <span class="remove-problem">X</span>
                        </div>`
                    );
                    $("#problem-search").val("");
                }

                $("#selected-problem-message").text("Problemas seleccionados: " + $("#selected-problems .problem").map(function () {
                    return $(this).text().trim();
                }).get().join(", "));
                $("#problem-dropdown-menu").hide();
            });
        }).fail(function (jqxhr, textStatus, error) {
            console.error("Error al cargar problems.json: ", textStatus, error);
        });
    }

// ✅ Ejecutar solo si estamos en problems.html
if (window.location.pathname.endsWith("problems.html")) {
    loadProblems();
}


    // Cargar al iniciar
    loadGroups();
    loadProblems();

    // Mostrar menús al enfocar input
    $("#group-search").on("focus", function () {
        adjustDropdownMenuPosition($(this), $("#group-dropdown-menu"));
        $("#group-dropdown-menu").show();
    });

    $("#problem-search").on("focus", function () {
        adjustDropdownMenuPosition($(this), $("#problem-dropdown-menu"));
        $("#problem-dropdown-menu").show();
    });

    // Ocultar dropdowns si se hace clic fuera
    $(document).on('mousedown', function (event) {
        if (!$(event.target).closest('#group-dropdown-menu, #group-search').length) {
            $("#group-dropdown-menu").hide();
        }
        if (!$(event.target).closest('#problem-dropdown-menu, #problem-search').length) {
            $("#problem-dropdown-menu").hide();
        }
    });

    // Generar informe
    $("#generate-report").on("click", function () {
        $("#status-message").text("Generando informe...");

        let selectedProblems = $("#selected-problems .problem").map(function () {
            return $(this).text().trim();
        }).get().join(", ");

    });

    // Reiniciar formulario
    $("#generate-new-report").on("click", function () {
        $("#group-search").val("");
        $("#selected-groups").empty();
        $("#selected-group-ids").val("");
        $("#problem-search").val("");
        $("#selected-problems").empty();
        $("#selected-problem-ids").val("");
        $("#generate-report").show();
        $("#start-date").val("");
        $("#end-date").val("");
        $(this).hide();
    });

    // Eliminar problema
    $("#selected-problems").on("click", ".remove-problem", function () {
        let problemId = $(this).parent().data('id');
        $("#selected-problems .problem[data-id='" + problemId + "']").remove();

        $("#selected-problem-message").text("Problemas seleccionados: " + $("#selected-problems .problem").map(function () {
            return $(this).text().trim();
        }).get().join(", "));
    });
});
