document.addEventListener("DOMContentLoaded", () => {
  const card = document.getElementById("musicCard");
  const toggleBtn = document.getElementById("musicToggleBtn");
  const closeBtn = document.getElementById("musicClose");
  const audio = document.getElementById("homeMusic");

  const playPauseBtn = document.getElementById("playPauseBtn");
  const nextBtn = document.getElementById("nextBtn");
  const prevBtn = document.getElementById("prevBtn");

  const playlist = JSON.parse(card.dataset.playlist);
  let index = 0;

  function loadSong() {
    audio.src = playlist[index];
  }

  function playSong() {
    audio.play();
    playPauseBtn.textContent = "⏸️";
  }

  function pauseSong() {
    audio.pause();
    playPauseBtn.textContent = "▶️";
  }

  toggleBtn.addEventListener("click", () => {
    card.classList.toggle("hidden");
  });

  closeBtn.addEventListener("click", () => {
    pauseSong();
    card.classList.add("hidden");
  });

  playPauseBtn.addEventListener("click", () => {
    audio.paused ? playSong() : pauseSong();
  });

  nextBtn.addEventListener("click", () => {
    index = (index + 1) % playlist.length;
    loadSong();
    playSong();
  });

  prevBtn.addEventListener("click", () => {
    index = (index - 1 + playlist.length) % playlist.length;
    loadSong();
    playSong();
  });

  loadSong();
});
