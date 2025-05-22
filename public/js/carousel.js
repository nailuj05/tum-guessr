const carousel = document.getElementById('carousel');
let cards = Array.from(carousel.children);

function render() {
	cards.forEach((card, i) => {
		card.className = 'card';
		if (i === 0) card.classList.add('cleft');
		else if (i === 1) card.classList.add('ccenter');
		else if (i === 2) card.classList.add('cright');
	});
} 
function rotateRight() {
	var c = cards.pop();
	cards.unshift(c);
	render();
}
function rotateLeft() {
	var c = cards.shift();
	cards.push(c);
	render();
}
cards.forEach((card, i) => {
	card.addEventListener('click', (event) => {
		if (card.classList.contains("cleft")) {
			rotateRight();
		} else if (card.classList.contains("cright")) {
			rotateLeft();
		} else {
			if(["garching"].includes(card.dataset.name))
				window.location.href = "/game?location="+card.dataset.name;
		}
	});
});

render();
