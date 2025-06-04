const element = document.getElementById('number-anim');
const final = parseInt(element.textContent, 10);
const duration = 2000;
let start = null;

function step(timestamp) {
  if (!start) start = timestamp;
  const progress = timestamp - start;
  const value = Math.min(Math.floor((progress / duration) * final), final);
  element.textContent = value;
  if (progress < duration) {
    requestAnimationFrame(step);
  }
}

element.textContent = '0';
requestAnimationFrame(step);
