//! Regenerates the Dart snapshot fixture without a Flutter/native loader.
use charpcut_editor_api::engine::Engine;

fn main() {
    let mut engine = Engine::new();
    engine.add_clip("content://media/IMG_0042.mp4", 4_000);
    let first = engine.snapshot().selected_clip_id.unwrap();
    engine.add_clip("/storage/emulated/0/DCIM/beach.mov", 6_000);
    engine.select(Some(&first));
    engine.split_selected(1_500);
    println!("{}", serde_json::to_string_pretty(&engine.snapshot()).unwrap());
}
