fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;
        // MSP host-only build: the portable installer gets the HGC IT logo.
        println!("cargo:rerun-if-env-changed=RUSTDESK_MSP_HOST");
        println!("cargo:rerun-if-changed=build.rs");
        let icon = if std::env::var("RUSTDESK_MSP_HOST").as_deref() == Ok("1") {
            "../../flutter/assets/msp_logo.ico"
        } else {
            "../../res/icon.ico"
        };
        println!("cargo:rerun-if-changed={icon}");
        let mut res = winres::WindowsResource::new();
        res.set_icon(icon)
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml");
        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
