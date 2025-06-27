document.addEventListener("DOMContentLoaded", () => {
    const applyStyles = () => {
        const tableCells = document.querySelectorAll("td");

        tableCells.forEach(cell => {
            if (cell.textContent.includes("[x]")) {
                cell.style.color = "green";
                cell.style.fontWeight = "bold";
            } else if (cell.textContent.includes("[ ]")) {
                cell.style.color = "red";
                cell.style.fontStyle = "italic";
            }
        });
    };

    // Apply styles initially
    applyStyles();

    // Re apply styles when <details> block is toggled
    const detailsElements = document.querySelectorAll("details");
    detailsElements.forEach(details => {
        details.addEventListener("toggle", applyStyles);
    });
});
