document.addEventListener("DOMContentLoaded", function () {
  const audio = document.getElementById("audioPlayer");
  const songs = document.querySelectorAll(".song");
  const playBtn = document.getElementById("playPauseBtn");
  const prevBtn = document.getElementById("prevBtn");
  const nextBtn = document.getElementById("nextBtn");
  const repeatBtn = document.getElementById("repeatBtn");
  const currentSongName = document.getElementById("currentSongName");

  let playlist = [];
  let currentIndex = 0;
  let isRepeating = false;

  songs.forEach((song, i) => {
    playlist.push({
      name: song.innerText,
      src: song.dataset.src,
    });

    song.addEventListener("click", () => {
      currentIndex = i;
      loadAndPlay();
    });
  });

  function loadAndPlay() {
    audio.src = playlist[currentIndex].src;
    currentSongName.innerText = "Playing: " + playlist[currentIndex].name;
    audio.play();
    playBtn.innerText = "⏸️";
  }

  playBtn.addEventListener("click", () => {
    if (audio.paused) {
      audio.play();
      playBtn.innerText = "⏸️";
    } else {
      audio.pause();
      playBtn.innerText = "▶️";
    }
  });

  nextBtn.addEventListener("click", () => {
    currentIndex = (currentIndex + 1) % playlist.length;
    loadAndPlay();
  });

  prevBtn.addEventListener("click", () => {
    currentIndex = (currentIndex - 1 + playlist.length) % playlist.length;
    loadAndPlay();
  });

  repeatBtn.addEventListener("click", () => {
    isRepeating = !isRepeating;
    repeatBtn.style.color = isRepeating ? "green" : "black";
  });

  audio.addEventListener("ended", () => {
    if (isRepeating) {
      loadAndPlay();
    } else {
      nextBtn.click();
    }
  });
});
