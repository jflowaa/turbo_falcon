export const SummaryToggle = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-toggle-summary]")) {
        const container = this.el;
        const summary = container.querySelector("[data-summary]");
        const original = container.querySelector("[data-original]");
        const label = container.querySelector("[data-toggle-label]");
        const isSummaryVisible = summary && summary.style.display !== "none";
        if (isSummaryVisible) {
          summary.style.display = "none";
          original.style.display = "";
          if (label) label.textContent = "Show summary";
        } else {
          summary.style.display = "";
          original.style.display = "none";
          if (label) label.textContent = "Show original";
        }
      }
    });
  },
};
