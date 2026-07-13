const revealElements = document.querySelectorAll(".reveal");

if ("IntersectionObserver" in window) {
  const revealObserver = new IntersectionObserver((entries, observer) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("visible");
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.12 });
  revealElements.forEach((element) => revealObserver.observe(element));
} else {
  revealElements.forEach((element) => element.classList.add("visible"));
}

const fleetTabs = Array.from(document.querySelectorAll('.fleet-tabs [role="tab"]'));
const fleetPanels = Array.from(document.querySelectorAll('[role="tabpanel"][data-fleet]'));

function activateFleetTab(tab, moveFocus = false) {
  fleetTabs.forEach((item) => {
    const selected = item === tab;
    item.classList.toggle("active", selected);
    item.setAttribute("aria-selected", String(selected));
    item.tabIndex = selected ? 0 : -1;
  });

  fleetPanels.forEach((panel) => {
    const selected = panel.dataset.fleet === tab.dataset.faction;
    panel.hidden = !selected;
    panel.classList.toggle("hidden", !selected);
  });

  if (moveFocus) tab.focus();
}

fleetTabs.forEach((tab, index) => {
  tab.addEventListener("click", () => activateFleetTab(tab));
  tab.addEventListener("keydown", (event) => {
    let targetIndex = index;
    if (event.key === "ArrowRight") targetIndex = (index + 1) % fleetTabs.length;
    else if (event.key === "ArrowLeft") targetIndex = (index - 1 + fleetTabs.length) % fleetTabs.length;
    else if (event.key === "Home") targetIndex = 0;
    else if (event.key === "End") targetIndex = fleetTabs.length - 1;
    else return;
    event.preventDefault();
    activateFleetTab(fleetTabs[targetIndex], true);
  });
});

const navShell = document.querySelector(".nav-shell");
if (navShell) {
  const updateNavigation = () => navShell.classList.toggle("scrolled", window.scrollY > 40);
  updateNavigation();
  window.addEventListener("scroll", updateNavigation, { passive: true });
}
