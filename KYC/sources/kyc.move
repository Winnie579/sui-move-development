module KYC::identity_kyc {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::string::String;
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::vector;

    // KYC status types
    public const STATUS_PENDING: u8 = 0;
    public const STATUS_APPROVED: u8 = 1;
    public const STATUS_REJECTED: u8 = 2;

    // Error Codes 
    const EALREADY_REGISTERED: u64 = 0;
    const ENOT_ADMIN: u64 = 1;
    const ENOT_FOUND: u64 = 2;

    // Admin singleton
    public struct Admin has key, store {
        id: UID,
        admin: address,
    }

    // Registry singleton
    public struct Registry has key, store {
        id: UID,
        registered: vector<address>,
    }

    // User identity object
    public struct UserIdentity has key, store {
        id: UID,
        user: address,
        name: String,
        kyc_status: u8,
        kyc_proofs: vector<String>,
        reputation_score: u64,
        created_at: u64,
        updated_at: u64,
    }

    // Events
    public struct UserRegistered has copy, drop {
        user: address,
        kyc_data_hash: String,
        name: String,
        timestamp: u64,
    }

    public struct KYCStatusUpdated has copy, drop {
        user: address,
        new_status: u8,
        old_status: u8,
        timestamp: u64,
    }

    // Initialize admin and registry (call once at deployment)
    public fun init(admin: address, ctx: &mut TxContext) {
        let admin_obj = Admin { id: sui::object::new(ctx), admin };
        let registry = Registry { id: sui::object::new(ctx), registered: vector::empty<address>() };
        transfer::transfer(admin_obj, admin);
        transfer::transfer(registry, admin);
    }

    // Helper: check if user is registered
    fun is_registered(registry: &Registry, user: address): bool {
        let n = vector::length(&registry.registered);
        let mut i = 0;
        while (i < n) {
            if (vector::borrow(&registry.registered, i) == &user) {
                return true;
            };
            i = i + 1;
        };
        false
    }

    // Register a new user
    public entry fun register_user(
        registry: &mut Registry,
        name: vector<u8>,
        kyc_data_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sender = sui::tx_context::sender(ctx);
        if (is_registered(registry, sender)) {
            abort EALREADY_REGISTERED;
        };

        let now = sui::clock::timestamp_ms(clock);
        let identity = UserIdentity {
            id: sui::object::new(ctx),
            user: sender,
            name: String::utf8(name),
            kyc_status: STATUS_PENDING,
            kyc_proofs: vector[String::utf8(kyc_data_hash)],
            reputation_score: 0,
            created_at: now,
            updated_at: now,
        };

        vector::push_back(&mut registry.registered, sender);
        transfer::transfer(identity, sender);
        event::emit(UserRegistered {
            user: sender,
            kyc_data_hash: String::utf8(kyc_data_hash),
            name: String::utf8(name),
            timestamp: now,
        });
    }

    // Add KYC proof document
    public entry fun add_kyc_proof(
        user_identity: &mut UserIdentity,
        proof: vector<u8>,
        ctx: &TxContext
    ) {
        let proof_string = String::utf8(proof);
        vector::push_back(&mut user_identity.kyc_proofs, proof_string);
    }

    // Admin-only: update KYC status
    public entry fun update_kyc_status(
        admin: &Admin,
        user_identity: &mut UserIdentity,
        new_status: u8,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sender = sui::tx_context::sender(ctx);
        if (sender != admin.admin) {
            abort ENOT_ADMIN;
        };
        let old_status = user_identity.kyc_status;
        user_identity.kyc_status = new_status;
        let now = sui::clock::timestamp_ms(clock);
        user_identity.updated_at = now;
        event::emit(KYCStatusUpdated {
            user: user_identity.user,
            old_status,
            new_status,
            timestamp: now,
        });
    }

    // Update reputation score
    public entry fun update_reputation(
        user_identity: &mut UserIdentity,
        delta: u64,
        ctx: &TxContext
    ) {
        user_identity.reputation_score = user_identity.reputation_score + delta;
    }

    // Public Getters 
    public fun get_kyc_status(user_identity: &UserIdentity): u8 {
        user_identity.kyc_status
    }

    public fun get_user(user_identity: &UserIdentity): address {
        user_identity.user
    }
}
