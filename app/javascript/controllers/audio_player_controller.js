import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "icon", "bar", "time"]
  static values = { src: String }

  toggle() {
    if (!this.audio) this.buildAudio()

    if (this.audio.paused) {
      this.audio.play()
    } else {
      this.audio.pause()
    }
  }

  buildAudio() {
    this.audio = new Audio(this.srcValue)
    this.audio.addEventListener("play", () => this.setPlaying(true))
    this.audio.addEventListener("pause", () => this.setPlaying(false))
    this.audio.addEventListener("ended", () => this.reset())
    this.audio.addEventListener("timeupdate", () => this.updateProgress())
  }

  setPlaying(playing) {
    this.iconTarget.textContent = playing ? "⏸" : "▶"
    this.toggleTarget.setAttribute("aria-label", playing ? "Pause recording" : "Play recording")
  }

  updateProgress() {
    const { currentTime, duration } = this.audio
    if (!duration) return

    this.barTarget.style.width = `${(currentTime / duration) * 100}%`
    this.timeTarget.textContent = this.formatTime(currentTime)
  }

  reset() {
    this.barTarget.style.width = "0%"
    this.timeTarget.textContent = "0:00"
    this.setPlaying(false)
  }

  formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  }
}
