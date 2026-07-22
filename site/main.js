// Mobile nav toggle — progressive enhancement only.
const navBtn = document.querySelector('[data-nav-toggle]');
const nav = document.querySelector('[data-nav]');
if (navBtn && nav) {
  navBtn.addEventListener('click', () => {
    const open = nav.classList.toggle('is-open');
    navBtn.setAttribute('aria-expanded', String(open));
  });
  // Close the menu after tapping a link (mobile).
  nav.querySelectorAll('a').forEach((a) => {
    a.addEventListener('click', () => {
      if (nav.classList.contains('is-open')) {
        nav.classList.remove('is-open');
        navBtn.setAttribute('aria-expanded', 'false');
      }
    });
  });
}

// Scroll reveals — sections slide in as they enter the viewport.
// Falls back to always-visible (no JS dependency for content).
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const revealables = document.querySelectorAll('.reveal, .reveal-stagger');
if (!reduceMotion && 'IntersectionObserver' in window) {
  // Opt into hidden-until-revealed only now that we KNOW we can reveal.
  document.documentElement.classList.add('js-reveal');
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          io.unobserve(entry.target);
        }
      });
    },
    // Top margin extends the root far upward so sections JUMPED past (anchor
    // links scroll instantly) still count as seen and reveal immediately.
    { threshold: 0.12, rootMargin: '9999px 0px -8% 0px' },
  );
  revealables.forEach((el) => io.observe(el));
} else {
  revealables.forEach((el) => el.classList.add('in-view'));
}

// Lead-capture forms → POST /api/lead. On any failure the hidden mailto
// fallback line is revealed, so a lead always has a way in.
document.querySelectorAll('form[data-lead-form]').forEach((form) => {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = form.querySelector('button[type="submit"]');
    const status = form.querySelector('.lead-status');
    const email = form.elements.email.value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      form.elements.email.focus();
      form.elements.email.setAttribute('aria-invalid', 'true');
      return;
    }
    form.elements.email.removeAttribute('aria-invalid');
    const label = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Sending…';
    try {
      const r = await fetch('/api/lead', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email,
          lang: form.elements.lang ? form.elements.lang.value : '',
          website: form.elements.website.value,
          page: location.pathname,
        }),
      });
      if (!r.ok) throw new Error(String(r.status));
      const done = document.createElement('p');
      done.className = 'lead-success';
      done.setAttribute('role', 'status');
      done.textContent = "You're in — one email the day it ships. Salamat!";
      form.replaceChildren(done);
    } catch {
      btn.disabled = false;
      btn.textContent = label;
      if (status) status.hidden = false;
    }
  });
});

// GoHighLevel embeds — form + calendar.
// To go live: paste your GHL widget URLs into the data-ghl-src attributes in
// index.html (form:  https://api.leadconnectorhq.com/widget/form/FORM_ID,
// calendar: https://api.leadconnectorhq.com/widget/booking/CALENDAR_ID).
// While an attribute is empty, the styled email fallback inside the slot stays.
document.querySelectorAll('[data-ghl-src]').forEach((slot) => {
  const src = slot.getAttribute('data-ghl-src');
  if (!src) return;
  const frame = document.createElement('iframe');
  frame.src = src;
  frame.className = 'contact-embed';
  frame.loading = 'lazy';
  frame.title = slot.getAttribute('data-ghl-title') || 'Contact';
  slot.replaceChildren(frame);
});
