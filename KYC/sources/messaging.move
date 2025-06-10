module messaging::messaging {
    use sui::event;
    use sui::tx_context::TxContext;
    use std::string::String;
    use std::option::Option;
    use sui::transfer;
    use sui::clock::Clock;
    use sui::object::{Self, UID};
    use KYC::identity_kyc::{Self, UserIdentity, get_kyc_status, STATUS_APPROVED};  // Import from sibling

    // Constants for message types
    const MSG_TYPE_RIDE: u8 = 0;
    const MSG_TYPE_PAYMENT: u8 = 1;
    const MSG_TYPE_KYC: u8 = 2;
    const MSG_TYPE_SUPPORT: u8 = 3; // Maximum supported message type

    // Message Constants 
    const MESSAGE_TYPE_TEMPLATE: u8 = 0xA0; // System-generated
    const MESSAGE_TYPE_QUICK_REPLY: u8 = 0xB0; // Passenger shortcuts
    const MESSAGE_TYPE_RIDE_THREAD: u8 = 0; // Messages within a ride thread

    // Driver Templates (0x0-)
    const TEMPLATE_DRIVER_EN_ROUTE: u8 = 0x0; // "Driver is on the way"
    const TEMPLATE_ARRIVING_SOON: u8 = 0x1;   // "Arriving in X mins"
    const TEMPLATE_ARRIVING_NOW: u8 = 0x2; // "Arriving now"
    const TEMPLATE_DRIVER_DELAYED: u8 = 0x3; // "Driver delayed"
    const TEMPLATE_DRIVER_CANCELLED: u8 = 0x4; // "Driver cancelled ride"
    const TEMPLATE_PAYMENT_RECEIVED: u8 = 0x5; // "Payment received"
    const TEMPLATE_RIDE_COMPLETED: u8 = 0x6;   // "Ride completed"

    // Passenger Quick-Replies (0x10-)
    const REPLY_ON_MY_WAY: u8 = 0x10;
    const REPLY_NEED_HELP: u8 = 0x11; // "Support request
    const REPLY_CANCEL_RIDE: u8 = 0x12; // "Cancel ride"
    const REPLY_RATE_DRIVER: u8 = 0x13; // "Rate driver"
    const TEMPLATE_PAYMENT_SENT: u8 = 0x14; // "Payment sent"
    
     // ====== Error Codes ======
    const EINVALID_MESSAGE_TYPE: u64 = 0;
    const EKYC_REQUIRED: u64 = 1;
    const ENOT_THREAD_MEMBER: u64 = 2;

    // Events
    public struct Message has key, store {
        id: UID,
        sender: address,
        thread_id: UID,       // Links messages in a conversation
        message_type: u8,  // 0 = Ride, 1 = Payment, 2 = KYC, 3 = Support
        content_hash: String,
        is_template: bool,  // True for auto-generated messages
        template_id: Option<u8>, // TEMPLATE_XXX if is_template
        timestamp: u64,
    }

    // Event for message sent
    public struct MessageSent has copy, drop {
        sender: address,
        recipient: address,
        message_hash: String,
        message_type: u8, 
        message_id: ID,
        timestamp: u64,
    }
    
    // Thread metadata (created per ride)
    public struct Thread has key {
        id: UID,
        ride_id: ID,         // Links to ride object
        driver: address,
        passenger: address,
        template_id: Option<u8>, // For auto-replies
        is_active: bool,    // True if ride is ongoing
        message_flags: u8,  // Bitmask: [is_template, is_reply, is_urgent]
        latest_eta: u64, // For template timing
        created_at: u64,
    }

    // Auto-generated message for templates
    public struct QuickReplyMenu has key {
        id: UID,
        passenger: address,
        enabled_replies: vector<u8>, // REPLY_XXX codes
    }

    /// Event for efficient indexing
    public struct NewThreadMessage has copy, drop {
        thread_id: ID,
        ride_id: ID,
        message_type: u8,
    }

    // Read receipt for message acknowledgment
    public struct ReadReceipt has key, store {
        id: UID,
        message_id: ID,
        reader: address,
        timestamp: u64,
   }

    public struct MessageStatus has key, store {
        id: UID,
        message_id: ID,
        reader: address,
        status: u8, // 0=unread, 1=delivered, 2=read
        timestamp: u64,
   } 
    // Initializer function
    fun init(ctx: &mut TxContext) {
        // Module initialization if needed
   }

    public entry fun store_message(
        recipient: address,
        content: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
   ) {
        let message = Message {
            id: sui::object::new(ctx),
            sender: sui::tx_context::sender(ctx),
            thread_id: sui::object::new(ctx), // Placeholder, update as needed
            message_type: MSG_TYPE_RIDE, // Placeholder, update as needed
            content_hash: String::utf8(content),
            is_template: false,
            template_id: option::none<u8>(),
            timestamp: sui::clock::timestamp_ms(clock),
    };
    sui::transfer::transfer(message, recipient); // Send as an object
}

    // Store a message hash (off-chain content referenced by hash)
    public entry fun send_message(
        recipient: address,
        message_type: u8,
        content_hash: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        
        let sender = sui::tx_context::sender(ctx);
        let hash_string = String::utf8(content_hash);
        let message = Message {
            id: sui::object::new(ctx),
            sender,
            thread_id: sui::object::new(ctx), // Placeholder, update as needed
            message_type,
            content_hash: hash_string,
            is_template: false,
            template_id: option::none<u8>(),
            timestamp: sui::clock::timestamp_ms(clock),
        };

        // Transfer to recipient
        sui::transfer::transfer(message, recipient);

        // Emit event for message sent
        sui::event::emit(MessageSent {
            sender,
            recipient,
            message_hash: hash_string,
            message_type,
            message_id: message.id,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }
    public entry fun notify_kyc_approved(
        user_identity: &UserIdentity,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext,
   ) {
     let message = b"KYC Approved. Ready to go places?";
     assert!(get_kyc_status(user_identity) == STATUS_APPROVED, EKYC_REQUIRED);

     send_message(
        recipient,
        MSG_TYPE_KYC,
        message,
        clock,
        ctx,
    );
   }
    
    // Create a new thread for ride communication
     public entry fun create_thread(
        ride_id: ID,
        participant: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let thread = Thread {
            id: sui::object::new(ctx),
            ride_id,
            driver: sui::tx_context::sender(ctx),
            passenger: participant,
            template_id: option::none<u8>(),
            is_active: true,
            message_flags: 0,
            latest_eta: 0,
            created_at: sui::clock::timestamp_ms(clock),
        };
        sui::transfer::share_object(thread); // Both participants can access
      }
    }

    /// 2. Send message within a thread (KYC needed for drivers)
    public entry fun send_thread_message(
        thread: &Thread,
        content_hash: vector<u8>,
        user_identity: &UserIdentity,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let sender = sui:tx_context::sender(ctx);
        assert!(
            sender == thread.driver || sender == thread.passenger,
            ENOT_THREAD_MEMBER
        );
        
        // Drivers need KYC, passengers don't
        if sender == thread.driver {
            assert!(get_kyc_status(user_identity) == STATUS_APPROVED, EKYC_REQUIRED);
        }
        let message = Message {
            id: sui:object::new(ctx),
            thread_id: thread.id,
            sender,
            message_type: MSG_TYPE_RIDE_THREAD,
            content_hash: String::utf8(content_hash),
            is_template: false,
            template_id: option::none<u8>(),
            timestamp: sui::clock::timestamp_ms(clock),
        };

         // Transfer to the other participant
        let recipient = if (sender == thread.driver) { thread.passenger } else { thread.driver };
        sui::transfer::transfer(message, recipient);

        sui::event::emit(NewThreadMessage {
            thread_id: thread.id,
            ride_id: thread.ride_id,
            message_type: MSG_TYPE_RIDE,
       });
    }

  //Add Read Receipts
    public entry fun acknowledge_message(
        message: &Message,
        clock: &Clock,
        ctx: &mut TxContext
  ) {
    let receipt = ReadReceipt {
        id: sui::object::new(ctx),
        message_id: object::id(message),
        reader: tx_context::sender(ctx),
        timestamp: sui::clock::timestamp_ms(clock)
    };
    sui::transfer::transfer(receipt, message.sender);
  }

// Message status (e.g., read, delivered)
    public entry fun update_status(
        message: &Message,
        status: u8, // 0 = unread, 1 = read, 2 = delivered
        clock: &Clock,
        ctx: &mut TxContext
) {
    let status_obj = MessageStatus {
        id: sui::object::new(ctx),
        message_id: object::id(message),
        reader: tx_context::sender(ctx),
        status,
        timestamp: sui::clock::timestamp_ms(clock)
    };
    sui::transfer::transfer(status_obj, message.sender);
}
    
// Get KYC status of a user
    public fun get_kyc_status(user_identity: &UserIdentity): u8 {
        user_identity.kyc_status
   }

    // Get user reputation score
    public fun get_reputation_score(user_identity: &UserIdentity): u64 {
        user_identity.reputation_score
    }

    // Get message by ID
    public entry fun get_message_by_id(message_id: ID): Option<Message> {
        object::get<Message>(message_id)
    }

    // Get thread by ID
    public entry fun get_thread_by_id(thread_id: ID): Option<Thread> {
        object::get<Thread>(thread_id)
    }

// Cleanup expired messages
    public entry fun cleanup_expired_messages(
        message: Message, // by value, not &Message or &mut Message
        clock: &Clock,
        threshold: u64
   ) {
    if (sui::clock::timestamp_ms(clock) - message.timestamp > threshold) {
        sui::object::delete(message.id);
    }
   }

// Auto-send "Driver En Route" message when ride starts
    public entry fun notify_driver_en_route(
        ctx: &mut TxContext,
        clock: &Clock,
        thread: &mut Thread
  ) {
        let content = b"Driver is on the way";
        let message = Message {
            id: object::new(ctx),
            thread_id: object::id(thread),
            sender: thread.driver,
            message_type: MESSAGE_TYPE_TEMPLATE,
            content_hash: String::utf8(content),
            is_template: true,
            template_id: option::some(TEMPLATE_DRIVER_EN_ROUTE),
            timestamp: clock::timestamp_ms(clock),
        };
        
        sui::transfer::transfer(message, thread.passenger);
        sui::event::emit(AutoMessageSent {
            thread_id: object::id(thread),
            template_id: TEMPLATE_DRIVER_EN_ROUTE
        });
    }

    /// Auto-send ETA update (called by driver's GPS)
    public entry fun update_eta(
        thread: &mut Thread,
        minutes_away: u8,
        driver_identity: &UserIdentity,
        clock: &Clock,
        ctx: &mut TxContext
   ) {
        let template_id = if (minutes_away == 0) {
        TEMPLATE_ARRIVING_NOW
    } else if (minutes_away <= 2) {
        TEMPLATE_ARRIVING_SOON
    } else {
        TEMPLATE_DRIVER_DELAYED
        return;
    };
    
    send_driver_template(
        thread,
        template_id,
        driver_identity,
        clock,
        ctx
    );
}

        // Driver sends automated status update
    public entry fun send_driver_template(
        thread: &Thread,
        template_id: u8,
        driver_identity: &UserIdentity,
        clock: &Clock,
        ctx: &mut TxContext
    ) {

        let content = match template_id {
            TEMPLATE_DRIVER_EN_ROUTE => b"Driver is en route",
            TEMPLATE_ARRIVING_NOW => b"Arriving at pickup now",
            TEMPLATE_DRIVER_DELAYED => b"Driver is delayed",
            TEMPLATE_ARRIVING_SOON => b"Arriving in 2 minutes",
            TEMPLATE_DRIVER_CANCELLED => b"Driver cancelled ride",
            TEMPLATE_RIDE_COMPLETED => b"Ride completed",
            _ => b""
        };
        assert!(template_id <= TEMPLATE_ARRIVING_NOW, 0);
        assert!(driver_identity.kyc_status == identity_kyc::STATUS_APPROVED, 1);

        create_template_message(
            thread,
            content,
            true,  // is_template
            false, // is_reply
            option::some(template_id),
            clock,
            ctx
        );
    }

    // Passenger sends quick-reply
    public entry fun send_quick_reply(
        reply_id: u8,
        thread: &Thread,
        reply_menu: &QuickReplyMenu,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let content = match reply_id {
            REPLY_ON_MY_WAY => b"I'm on my way",
            REPLY_NEED_HELP => b"I need assistance",
            REPLY_CANCEL_RIDE => b"Please cancel the ride",
            REPLY_RATE_DRIVER => b"Rate the driver",
            TEMPLATE_PAYMENT_SENT => b"Payment sent",
            _ => b""
        };
        
        // Ensure the reply is enabled in the menu
        assert!(vector::contains(&reply_menu.enabled_replies, &reply_id), 0);

        // Reuse the same message creation logic as in send_driver_template and update_eta
        create_template_message(
            thread,
            content,
            false, // is_template
            true,  // is_reply
            option::some(reply_id),
            clock,
            ctx
        );
    }

    // Helper Functions 
    fun create_template_message(
        thread: &Thread,
        content: vector<u8>,
        is_template: bool,
        is_reply: bool,
        template_id: option::Option<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let message = Message {
            id: sui::object::new(ctx),
            thread_id: object::id(thread),
            sender: tx_context::sender(ctx),
            message_type: if is_template { MESSAGE_TYPE_TEMPLATE } else { MESSAGE_TYPE_QUICK_REPLY },
            content: content,
            is_template: is_template,
            template_id: template_id,
            timestamp: sui::clock::timestamp_ms(clock),
    });
        // Send to both parties
        sui::transfer::transfer(message, thread.driver);  // Send to driver
        // If you want to send to passenger as well, create a second message object
    let message2 = Message {
        id: sui::object::new(ctx),
        thread_id: object::id(thread),
        sender: tx_context::sender(ctx),
        message_type: if is_template { MESSAGE_TYPE_TEMPLATE } else { MESSAGE_TYPE_QUICK_REPLY },
        content: content,
        is_template: is_template,
        template_id: template_id,
        timestamp: sui::clock::timestamp_ms(clock),
    };
    sui::transfer::transfer(message2, thread.passenger);
}
