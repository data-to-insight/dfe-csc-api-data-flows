
// coerce sticky header so that it changes to reflect TOC heading currently in view
// if no TOC structure, stays on default title
document.addEventListener("DOMContentLoaded", function () {
    const headerTitle = document.querySelector(".md-header__title"); // ribbon title element
    const sections = document.querySelectorAll("h1, h2"); // target headings (dropped h3)

    function updateHeaderTitle() {
        let currentHeading = "CSC API Dataflow"; // default title when no section in view
        let scrollPosition = window.scrollY;

        sections.forEach((section) => {
            const offset = section.offsetTop - 50; // offset for sticky header height
            if (scrollPosition >= offset) {
                currentHeading = section.innerText;
            }
        });

        headerTitle.textContent = currentHeading;
    }

    window.addEventListener("scroll", updateHeaderTitle); // update title on scroll
});
