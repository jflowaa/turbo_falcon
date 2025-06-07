export const LocalTimeTooltip = {
  mounted() {
    this.updateLocalTime();
  },
  updated() {
    this.updateLocalTime();
  },
  updateLocalTime() {
    const utc = this.el.getAttribute("data-utc");
    if (!utc) return;
    const date = new Date(utc);
    if (isNaN(date.getTime())) return;
    const localString = date.toLocaleString();
    const localSpan = this.el.querySelector("[data-localtime]");
    if (localSpan) {
      localSpan.textContent = localString;
    } else {
      this.el.textContent = localString;
    }
  },
};
