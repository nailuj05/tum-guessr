const imgWrapper = document.querySelector('.image-wrapper');
let scale = 1;
let isDragging = false;
let lastX, lastY;
let currentX = 0, currentY = 0;

// TODO: reset zoom after a few seconds

window.addEventListener('wheel', (event) => {
    event.preventDefault();
    if (event.deltaY < 0) {
        scale = Math.min(scale * 1.1, 3); // zoom in
    } else {
        scale = Math.max(scale / 1.1, 1); // zoom out
    }
    imgWrapper.style.transform = `scale(${scale}) translate(${currentX * scale / 2}px, ${currentY * scale / 2}px)`;
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
				imgWrapper.style.transform = `scale(${scale}) translate(${currentX}px, ${currentY}px)`;
		}
});

window.addEventListener('mouseup', () => {
    isDragging = false;
    imgWrapper.style.cursor = 'grab';
});

