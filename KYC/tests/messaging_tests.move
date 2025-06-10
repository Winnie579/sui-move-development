#[test_only]
module messaging::messaging_tests {
    use sui::test_scenario;
    use sui::tx_context;
    use sui::clock;
    use sui::object;
    use std::string;
    use std::vector;
    use std::option;
    use messaging::messaging;
    use KYC::identity_kyc;

    // Test addresses
    const TEST_DRIVER: address = @0xDRIVER;
    const TEST_PASSENGER: address = @0xPASSENGER;
    const TEST_STRANGER: address = @0xSTRANGER;
    const TEST_ADMIN: address = @0xADMIN;

    #[test_only]
    fun setup_test_ride(ctx: &mut tx_context::TxContext): (ID, identity_kyc::UserIdentity) {
        let ride_id = object::new(ctx);
        let driver_identity = identity_kyc::create_verified_identity(TEST_DRIVER, ctx);
        (object::id(&ride_id), driver_identity)
    }

    #[test_only]
    fun create_test_thread(
        ride_id: ID,
        clock: &clock::Clock,
        ctx: &mut tx_context::TxContext
    ): messaging::Thread {
        messaging::create_thread(
            ride_id,
            TEST_PASSENGER,
            clock,
            ctx
        );
        test_scenario::take_shared<messaging::Thread>(ctx)
    }
}

    // Test sending and receiving a message between driver and passenger
    #[test]
    fun test_send_and_receive_message() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        
        let content = b"Hello passenger!";
        let content_hash = string::utf8(content);
        
        // Send message
        messaging::send_message(
            TEST_PASSENGER,
            messaging::MSG_TYPE_RIDE,
            content_hash,
            &clock,
            ctx
        );
        
        // Verify message received
        test_scenario::next_tx(&mut scenario, TEST_PASSENGER);
        let message = test_scenario::take_from_sender<messaging::Message>(&mut scenario);
        assert!(message.sender == TEST_DRIVER, 0);
        assert!(message.message_type == messaging::MSG_TYPE_RIDE, 1);
        assert!(string::bytes(&message.content_hash) == content, 2);

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = messaging::EINVALID_MESSAGE_TYPE)]
    fun test_send_invalid_message_type_fails() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        
        messaging::send_message(
            TEST_PASSENGER,
            255, // Invalid message type
            string::utf8(b"Invalid"),
            &clock,
            ctx
        );
        
        test_scenario::end(scenario);
    }

    // Test thread creation and messaging between driver and passenger
        #[test]
    fun test_thread_creation_and_messaging() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        let (ride_id, driver_identity) = setup_test_ride(ctx);
        
        // Create thread
        let thread = create_test_thread(ride_id, &clock, ctx);
        assert!(thread.participant_1 == TEST_DRIVER, 0);
        assert!(thread.participant_2 == TEST_PASSENGER, 1);
        
        // Send message in thread
        let message_content = string::utf8(b"Driver is coming");
        messaging::send_thread_message(
            &thread,
            message_content,
            &driver_identity,
            &clock,
            ctx
        );
        
        // Verify both participants receive message
        test_scenario::next_tx(&mut scenario, TEST_DRIVER);
        let driver_msg = test_scenario::take_from_sender<messaging::Message>(&mut scenario);
        test_scenario::next_tx(&mut scenario, TEST_PASSENGER);
        let passenger_msg = test_scenario::take_from_sender<messaging::Message>(&mut scenario);
        
        assert!(driver_msg.thread_id == object::id(&thread), 2);
        assert!(passenger_msg.thread_id == object::id(&thread), 3);

        test_scenario::end(scenario);
    }

    // Test non-member cannot send messages to thread
    #[test]
    #[expected_failure(abort_code = messaging::ENOT_THREAD_MEMBER)]
    fun test_non_member_cannot_send_to_thread() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        let (ride_id, _) = setup_test_ride(ctx);
        
        let thread = create_test_thread(ride_id, &clock, ctx);
        
        // Stranger tries to send message
        test_scenario::next_tx(&mut scenario, TEST_STRANGER);
        let ctx_stranger = test_scenario::ctx(&mut scenario);
        
        messaging::send_thread_message(
            &thread,
            string::utf8(b"I'm not in this thread"),
            &identity_kyc::create_verified_identity(TEST_STRANGER, ctx_stranger),
            &clock,
            ctx_stranger
        );
        
        test_scenario::end(scenario);
    }

    // Test unverified driver cannot send messages
        #[test]
    #[expected_failure(abort_code = messaging::EKYC_REQUIRED)]
    fun test_unverified_driver_cannot_message() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        let (ride_id, _) = setup_test_ride(ctx);
        
        let thread = create_test_thread(ride_id, &clock, ctx);
        let unverified_identity = identity_kyc::create_unverified_identity(TEST_DRIVER, ctx);
        
        messaging::send_thread_message(
            &thread,
            string::utf8(b"Unverified message"),
            &unverified_identity,
            &clock,
            ctx
        );
        
        test_scenario::end(scenario);
    }

    // Test KYC notification flow
    #[test]
    fun test_kyc_notification_flow() {
        let scenario = test_scenario::begin(TEST_ADMIN);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        
        let user_identity = identity_kyc::create_verified_identity(TEST_PASSENGER, ctx);
        
        messaging::notify_kyc_approved(
            &user_identity,
            TEST_PASSENGER,
            &clock,
            b"KYC Approved!",
            ctx
        );
        
        // Verify notification was sent
        test_scenario::next_tx(&mut scenario, TEST_PASSENGER);
        let message = test_scenario::take_from_sender<messaging::Message>(&mut scenario);
        assert!(message.message_type == messaging::MSG_TYPE_KYC, 0);
        assert!(message.sender == TEST_ADMIN, 1);

        test_scenario::end(scenario);
    }

          
       
        // Verify template message
        #[test]
    fun test_driver_template_messages() {
        let scenario = test_scenario::begin(TEST_DRIVER);
        let clock = clock::create_for_testing(@0x0);
        let ctx = test_scenario::ctx(&mut scenario);
        let (ride_id, driver_identity) = setup_test_ride(ctx);
        
        let thread = create_test_thread(ride_id, &clock, ctx);
        
        // Send driver en route template
        messaging::send_driver_template(
            &thread,
            messaging::TEMPLATE_DRIVER_EN_ROUTE,
            &driver_identity,
            &clock,
            ctx
        );
        
        // Verify template message
        test_scenario::next_tx(&mut scenario, TEST_PASSENGER);
        let message = test_scenario::take_from_sender<messaging::Message>(&mut scenario);
        assert!(option::is_some(&message.template_id), 0);
        assert!(option::extract(&mut message.template_id) == messaging::TEMPLATE_DRIVER_EN_ROUTE, 1);
        assert!(message.is