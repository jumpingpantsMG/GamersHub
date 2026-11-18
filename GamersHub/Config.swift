import Foundation
import Supabase

enum Config {
    // Supabase dashboard > Project Settings > API
    static let supabaseURL = URL(string: "https://qyfzhgqrvkbviipfglsk.supabase.co")!
    static let supabaseAnonKey = "sb_publishable_GX19kgYWlnb1J3cuZczOWg_0fYbWvk-"
}

let supabase = SupabaseClient(
    supabaseURL: Config.supabaseURL,
    supabaseKey: Config.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
    )
)
