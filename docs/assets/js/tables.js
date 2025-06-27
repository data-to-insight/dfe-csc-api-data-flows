document.addEventListener("DOMContentLoaded", function () {
    // Ensure all tables have the sortable class
    document.querySelectorAll("table").forEach((table) => {
        table.classList.add("sortable");
    });

    // Force initialise Material for MkDocs JavaScript components
    if (window.Components && window.Components.initialize) {
        console.log("Re-initialising MkDocs Material Components...");
        window.Components.initialize();
    } else {
        console.warn("MkDocs Material components not found. Manually loading script...");

        // Attempt to dynamically load the missing Material JS
        let script = document.createElement("script");
        script.src = "https://cdn.jsdelivr.net/npm/@squidfunk/mkdocs-material@latest/assets/javascripts/bundle.js";
        script.onload = function () {
            if (window.Components && window.Components.initialize) {
                console.log("Material Components loaded, initialising...");
                window.Components.initialize();
            } else {
                console.error("Failed to initialise MkDocs Material Components.");
            }
        };
        document.head.appendChild(script);
    }
});
