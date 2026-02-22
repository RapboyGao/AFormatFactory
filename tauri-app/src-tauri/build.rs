use std::env;
use std::path::PathBuf;

fn main() {
    tauri_build::build();

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("missing manifest dir"));
    let project_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("failed to resolve project root")
        .to_path_buf();

    let ffmpeg_include = project_root.join("ThirdParty/ffmpeg-install/include");
    let ffmpeg_lib = project_root.join("ThirdParty/ffmpeg-install/lib");
    let c_src = project_root.join("Sources/AFormatFactoryFFmpegC");

    println!("cargo:rerun-if-changed={}", c_src.join("AFormatFactoryFFmpegC.c").display());
    println!("cargo:rerun-if-changed={}", c_src.join("AFormatFactoryFFmpegC_MediaEdit.c").display());
    println!("cargo:rerun-if-changed={}", c_src.join("AFormatFactoryFFmpegC_Probe.c").display());
    println!("cargo:rerun-if-changed={}", c_src.join("AFormatFactoryFFmpegC_Internal.h").display());
    println!("cargo:rerun-if-changed={}", c_src.join("include/AFormatFactoryFFmpegC.h").display());

    cc::Build::new()
        .include(c_src.join("include"))
        .include(&ffmpeg_include)
        .file(c_src.join("AFormatFactoryFFmpegC.c"))
        .file(c_src.join("AFormatFactoryFFmpegC_MediaEdit.c"))
        .file(c_src.join("AFormatFactoryFFmpegC_Probe.c"))
        .compile("aformatfactory_ffmpegc");

    println!("cargo:rustc-link-search=native={}", ffmpeg_lib.display());
    println!("cargo:rustc-link-lib=static=avformat");
    println!("cargo:rustc-link-lib=static=avcodec");
    println!("cargo:rustc-link-lib=static=avfilter");
    println!("cargo:rustc-link-lib=static=swresample");
    println!("cargo:rustc-link-lib=static=swscale");
    println!("cargo:rustc-link-lib=static=avutil");
    println!("cargo:rustc-link-lib=z");
    println!("cargo:rustc-link-lib=bz2");
    println!("cargo:rustc-link-lib=iconv");
    println!("cargo:rustc-link-lib=m");

    println!("cargo:rustc-link-lib=framework=VideoToolbox");
    println!("cargo:rustc-link-lib=framework=CoreMedia");
    println!("cargo:rustc-link-lib=framework=CoreVideo");
    println!("cargo:rustc-link-lib=framework=AudioToolbox");
    println!("cargo:rustc-link-lib=framework=AVFoundation");
    println!("cargo:rustc-link-lib=framework=CoreImage");
    println!("cargo:rustc-link-lib=framework=OpenGL");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Security");
}
