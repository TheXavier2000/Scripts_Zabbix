$(document).ready(function() {
    // Función para agregar botones personalizados al selector de fecha
    function addCustomButtons(input) {
        setTimeout(function() {
            let buttonPane = $(input).datepicker("widget").find(".ui-datepicker-buttonpane");

            // Eliminar el botón "Done"
            buttonPane.find(".ui-datepicker-close").remove();

            // Botón para seleccionar la fecha de hoy
            if (buttonPane.find(".ui-datepicker-today").length === 0) {
                $("<button>", {
                    text: "Hoy",
                    class: "ui-datepicker-today ui-state-default ui-priority-primary ui-corner-all",
                    click: function() {
                        let today = new Date();
                        today.setHours(0, 0, 0, 0);  // Ajustar la hora a 00:00:00 local
                        $(input).datepicker('setDate', today);
                        $(input).datepicker("hide");
                    }
                }).appendTo(buttonPane);
            }

            // Botón para borrar la fecha seleccionada
            if (buttonPane.find(".ui-datepicker-clear").length === 0) {
                $("<button>", {
                    text: "Borrar",
                    class: "ui-datepicker-clear ui-state-default ui-priority-primary ui-corner-all",
                    click: function() {
                        $(input).val("");
                        $(input).datepicker("hide");
                    }
                }).appendTo(buttonPane);
            }
        }, 1);
    }

    // Inicializar el selector de fecha de inicio
    $("#start-date").datepicker({
        dateFormat: "yy-mm-dd",  // Asegurar consistencia en el formato
        onSelect: function(selectedDate) {
            // No necesitas convertir el formato aquí
            // Simplemente usa el valor seleccionado directamente
            let startDate = $.datepicker.parseDate("yy-mm-dd", selectedDate);

            // Actualizar el campo de fecha con la fecha seleccionada
            $("#start-date").datepicker('setDate', startDate);  

            // Establecer la fecha mínima en el campo de fecha de fin
            $("#end-date").datepicker("option", "minDate", startDate);
            
            // Habilitar el campo de fecha de fin
            $("#end-date").prop("disabled", false);
        },
        beforeShow: function(input, inst) {
            addCustomButtons(input);  // Función personalizada para botones
        },
        showButtonPanel: true
    });

    // Inicializar el selector de fecha de fin
    $("#end-date").prop("disabled", true).datepicker({
        dateFormat: "yy-mm-dd",  // Mantener el mismo formato que el de la fecha de inicio
        maxDate: 0,
        onSelect: function(selectedDate) {
            // Usar el mismo formato de la fecha para convertirla
            let endDate = $.datepicker.parseDate("yy-mm-dd", selectedDate);
            
            // Ajustar la hora al final del día si es necesario (esto no afectará la selección de la fecha)
            endDate.setHours(23, 59, 59, 999);  
            
            // Actualizar el campo de fecha con la fecha seleccionada
            $("#end-date").datepicker('setDate', endDate);
            
            // Verificar si la fecha de fin es anterior a la fecha de inicio
            let startDate = $("#start-date").datepicker('getDate');
            if (startDate && endDate < startDate) {
                // Si la fecha final es anterior a la de inicio, ajustar la fecha de inicio
                $("#start-date").datepicker("setDate", endDate);
            }
        },
        beforeShow: function(input, inst) {
            addCustomButtons(input);  // Función personalizada para botones
        },
        showButtonPanel: true
    });

    // Limpiar las fechas seleccionadas
    $("#clear-dates").click(function() {
        $("#start-date").val("");
        $("#end-date").val("");
        $("#end-date").prop("disabled", true);
    });
});
