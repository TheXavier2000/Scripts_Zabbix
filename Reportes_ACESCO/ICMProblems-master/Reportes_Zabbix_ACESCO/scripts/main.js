// Cargar scripts compartidos
$.getScript("../scripts/dates.js")
    .done(() => console.log("dates.js cargado correctamente."))
    .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar dates.js:", textStatus, errorThrown));

$.getScript("../scripts/jsonQueries.js")
    .done(() => console.log("jsonQueries.js cargado correctamente."))
    .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar jsonQueries.js:", textStatus, errorThrown));

$.getScript("../scripts/filters.js")
    .done(() => console.log("filters.js cargado correctamente."))
    .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar filters.js:", textStatus, errorThrown));

// Detectar la página y cargar solo el script necesario
const currentPage = window.location.pathname;

if (currentPage.endsWith("problems.html")) {
    $.getScript("../scripts/reportGenerationProblems.js")
        .done(() => console.log("reportGenerationProblems.js cargado correctamente."))
        .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar reportGenerationProblems.js:", textStatus, errorThrown));
} else if (currentPage.endsWith("availability.html")) {
    $.getScript("../scripts/reportGenerationAlvailability.js")
        .done(() => console.log("reportGenerationAlvailability.js cargado correctamente."))
        .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar reportGenerationAlvailability.js:", textStatus, errorThrown));
} else if (currentPage.endsWith("baseline.html")) {
    $.getScript("../scripts/reportGenerationBaseLine.js")
        .done(() => console.log("reportGenerationBaseLine.js cargado correctamente."))
        .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar reportGenerationBaseLine.js:", textStatus, errorThrown));
} else if (currentPage.endsWith("metrics.html")) {
    $.getScript("../scripts/reportGenerationMetrics.js")
        .done(() => console.log("reportGenerationMetrics.js cargado correctamente."))
        .fail((jqXHR, textStatus, errorThrown) => console.error("Error al cargar reportGenerationMetrics.js:", textStatus, errorThrown));
}


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
    }, 4000); // Duración: 4 segundos
}
