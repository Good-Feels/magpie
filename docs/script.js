const revealObserver = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) {
      entry.target.classList.add("show");
      revealObserver.unobserve(entry.target);
    }
  }
}, { threshold: 0.12 });

document.querySelectorAll(".reveal").forEach((el, i) => {
  el.style.transitionDelay = `${Math.min(i * 80, 280)}ms`;
  revealObserver.observe(el);
});

document.querySelectorAll(".shot img").forEach((img) => {
  img.addEventListener("error", () => {
    const shot = img.closest(".shot");
    if (shot) shot.classList.add("is-fallback");
  }, { once: true });

  if (img.complete && img.naturalWidth === 0) {
    const shot = img.closest(".shot");
    if (shot) shot.classList.add("is-fallback");
  }
});
