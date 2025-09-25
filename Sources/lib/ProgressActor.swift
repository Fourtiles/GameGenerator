import Progress

actor ProgressActor {
  var bar: ProgressBar

  init(count: Int) {
    bar = ProgressBar(count: count)
  }

  func next() { bar.next() }
}
