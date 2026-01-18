fn main() {
    #[cfg(target_os = "windows")]
    {
        embed_resource::compile("resources/app.rc", embed_resource::NONE);
    }
}
