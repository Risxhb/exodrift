const revealObserver = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) entry.target.classList.add("visible");
  }
}, { threshold: 0.12 });

document.querySelectorAll(".reveal").forEach((element) => revealObserver.observe(element));

document.querySelectorAll(".fleet-tabs button").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".fleet-tabs button").forEach((item) => item.classList.remove("active"));
    document.querySelectorAll("[data-fleet]").forEach((fleet) => fleet.classList.add("hidden"));
    button.classList.add("active");
    document.querySelector(`[data-fleet="${button.dataset.faction}"]`).classList.remove("hidden");
  });
});

window.addEventListener("scroll", () => {
  document.querySelector(".nav-shell").classList.toggle("scrolled", window.scrollY > 40);
}, { passive: true });
