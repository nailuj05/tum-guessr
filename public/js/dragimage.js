const imgWrapper = document.querySelector('.image-wrapper');
let scale = 1;
let isDragging = false;
let lastX, lastY;
let currentX = 0, currentY = 0;
let initialDistance = null;
let lastScale = 1;

function applyTransform() {
  imgWrapper.style.transform = `scale(${scale}) translate(${currentX}px, ${currentY}px)`;
}

window.addEventListener('wheel', (event) => {
  event.preventDefault();
  if (event.deltaY < 0) {
    scale = Math.min(scale * 1.1, 3); // zoom in
  } else {
    scale = Math.max(scale / 1.1, 1); // zoom out
  }
	applyTransform();
});

imgWrapper.addEventListener('mousedown', (event) => {
	event.preventDefault();
  isDragging = true;
  lastX = event.clientX / scale;
  lastY = event.clientY / scale;
  initialX = imgWrapper.offsetLeft;
  initialY = imgWrapper.offsetTop;
  imgWrapper.style.cursor = 'grabbing';
});

window.addEventListener('mousemove', (event) => {
  if (isDragging) {
    const dx = (event.clientX / scale) - lastX;
		const dy = (event.clientY / scale) - lastY;
		currentX += dx;
		currentY += dy;
		lastX = event.clientX / scale;
		lastY = event.clientY / scale;
		applyTransform();
	}
});

window.addEventListener('mouseup', () => {
  isDragging = false;
  imgWrapper.style.cursor = 'grab';
});

imgWrapper.addEventListener('touchstart', (e) => {
  if (e.touches.length === 1) {
    isDragging = true;
    lastX = e.touches[0].clientX / scale;
    lastY = e.touches[0].clientY / scale;
  } else if (e.touches.length === 2) {
    isDragging = false;
    const dx = e.touches[1].clientX - e.touches[0].clientX;
    const dy = e.touches[1].clientY - e.touches[0].clientY;
    initialDistance = Math.hypot(dx, dy);
    lastScale = scale;
  }
});

imgWrapper.addEventListener('touchmove', (e) => {
  e.preventDefault();
  if (e.touches.length === 1 && isDragging) {
    const dx = (e.touches[0].clientX / scale) - lastX;
    const dy = (e.touches[0].clientY / scale) - lastY;
    currentX += dx;
    currentY += dy;
    lastX = e.touches[0].clientX / scale;
    lastY = e.touches[0].clientY / scale;
    applyTransform();
  } else if (e.touches.length === 2 && initialDistance) {
    const dx = e.touches[1].clientX - e.touches[0].clientX;
    const dy = e.touches[1].clientY - e.touches[0].clientY;
    const currentDistance = Math.hypot(dx, dy);
    scale = Math.min(Math.max(lastScale * (currentDistance / initialDistance), 1), 3);
    applyTransform();
  }
}, { passive: false });

imgWrapper.addEventListener('touchend', (e) => {
  if (e.touches.length === 0) {
    isDragging = false;
    initialDistance = null;
  }
});
