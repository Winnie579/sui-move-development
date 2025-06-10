#[test_only]
module KYC::identity_kyc_tests {
    use sui::test_scenario;
    use sui::tx_context;
    use std::string;
    use KYC::identity_kyc::{Self, UserIdentity, AdminCap, UserRegistered, KYCStatusUpdated};

    const TEST_NAME: vector<u8> = b"Mary Lou";
    const TEST_PROOF: vector<u8> = b"proof_document_hash";

    #[test]
    fun test_register_user() {
        let scenario = test_scenario::begin(@0x123);
        let user = test_scenario::next_sender(&scenario);
        
        // Test user registration
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        
        // Verify event emission
        let events = test_scenario::take_events(&scenario);
        let user_registered_event = events[0];
        assert!(std::string::utf8(TEST_NAME) == user_registered_event.name, 0);
        assert!(user == user_registered_event.user_address, 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_kyc_proof() {
        let scenario = test_scenario::begin(@0x123);
        let user = test_scenario::next_sender(&scenario);
        
        // Register user first
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // Test adding KYC proof
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::add_kyc_proof(&mut user_identity, TEST_PROOF, test_scenario::ctx(&mut scenario));
        
        // Verify proof was added
        assert!(vector::length(&user_identity.kyc_proofs) == 1, 0);
        assert!(*vector::borrow(&user_identity.kyc_proofs, 0) == std::string::utf8(TEST_PROOF), 1);
        
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_add_kyc_proof_unauthorized() {
        let scenario = test_scenario::begin(@0x123);
        let user1 = test_scenario::next_sender(&scenario);
        let user2 = test_scenario::next_sender(&scenario);
        
        // User1 registers
        test_scenario::next_tx(&mut scenario, user1);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // User2 tries to add proof (should fail)
        test_scenario::next_tx(&mut scenario, user2);
        identity_kyc::add_kyc_proof(&mut user_identity, TEST_PROOF, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_kyc_status() {
        let scenario = test_scenario::begin(@0x123);
        let admin = test_scenario::next_sender(&scenario);
        let user = test_scenario::next_sender(&scenario);
        
        // Create admin capability
        let admin_cap = AdminCap { id: tx_context::new_id(test_scenario::ctx(&mut scenario)) };
        test_scenario::transfer_to_sender(&mut scenario, admin_cap);
        
        // Register user
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // Admin updates KYC status
        test_scenario::next_tx(&mut scenario, admin);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        identity_kyc::update_kyc_status(&mut user_identity, identity_kyc::STATUS_APPROVED, &admin_cap, test_scenario::ctx(&mut scenario));
        
        // Verify status update
        assert!(user_identity.kyc_status == identity_kyc::STATUS_APPROVED, 0);
        
        // Verify event emission
        let events = test_scenario::take_events(&scenario);
        let status_updated_event = events[1]; // First event is UserRegistered
        assert!(user == status_updated_event.user_address, 1);
        assert!(identity_kyc::STATUS_APPROVED == status_updated_event.new_status, 2);
        
        test_scenario::return_to_sender(&mut scenario, admin_cap);
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_update_kyc_status_invalid() {
        let scenario = test_scenario::begin(@0x123);
        let admin = test_scenario::next_sender(&scenario);
        let user = test_scenario::next_sender(&scenario);
        
        // Create admin capability
        let admin_cap = AdminCap { id: tx_context::new_id(test_scenario::ctx(&mut scenario)) };
        test_scenario::transfer_to_sender(&mut scenario, admin_cap);
        
        // Register user
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // Try to set invalid status (should fail)
        test_scenario::next_tx(&mut scenario, admin);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        identity_kyc::update_kyc_status(&mut user_identity, 3, &admin_cap, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_to_sender(&mut scenario, admin_cap);
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_reputation() {
        let scenario = test_scenario::begin(@0x123);
        let user = test_scenario::next_sender(&scenario);
        
        // Register user
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // Update reputation
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::update_reputation(&mut user_identity, 10, test_scenario::ctx(&mut scenario));
        
        // Verify reputation update
        assert!(user_identity.reputation_score == 10, 0);
        
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_update_reputation_unauthorized() {
        let scenario = test_scenario::begin(@0x123);
        let user1 = test_scenario::next_sender(&scenario);
        let user2 = test_scenario::next_sender(&scenario);
        
        // User1 registers
        test_scenario::next_tx(&mut scenario, user1);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // User2 tries to update reputation (should fail)
        test_scenario::next_tx(&mut scenario, user2);
        identity_kyc::update_reputation(&mut user_identity, 10, test_scenario::ctx(&mut scenario));
        
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_initial_state() {
        let scenario = test_scenario::begin(@0x123);
        let user = test_scenario::next_sender(&scenario);
        
        // Register user
        test_scenario::next_tx(&mut scenario, user);
        identity_kyc::register_user(TEST_NAME, test_scenario::ctx(&mut scenario));
        let user_identity = test_scenario::take_from_sender<UserIdentity>(&scenario);
        
        // Verify initial state
        assert!(user_identity.owner == user, 0);
        assert!(user_identity.name == std::string::utf8(TEST_NAME), 1);
        assert!(user_identity.kyc_status == identity_kyc::STATUS_PENDING, 2);
        assert!(user_identity.reputation_score == 0, 3);
        assert!(vector::is_empty(&user_identity.kyc_proofs), 4);
        
        test_scenario::return_to_sender(&mut scenario, user_identity);
        test_scenario::end(scenario);
    }
}