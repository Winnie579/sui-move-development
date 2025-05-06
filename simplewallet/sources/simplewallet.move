module suiwallet::wallet {
   use sui::coin::{Self,Coin};
   use sui::sui::SUI;
   use sui::balance::{Self,Balance};

   public struct Wallet has key, store {
     id: UID,
     balance: Balance<SUI>,
     owner: address 
     }
// Create a new empty wallet 
   public entry fun create_wallet(ctx: &mut TxContext) { 
      let sender = tx_context::sender(ctx);
      let wallet = Wallet {
       id: object::new(ctx),
       balance: balance:: zero<SUI>(),
       owner: sender
      }; 
// Transfer wallet to the creator    
   transfer::transfer(wallet,sender);
   }
// Deposit SUI coins   
   public entry fun deposit(wallet: &mut Wallet, coin:Coin<SUI>, _ctx: &mut TxContext) {
      let coin_balance = coin::into_balance(coin);
      balance::join(&mut wallet.balance, coin_balance);
   }
// Transfer SUI from wallet to another address   
   public entry fun transfer_to(wallet: &mut Wallet, amount: u64, recipient: address, ctx: &mut TxContext) {
       // Check if the sender is the owner 
       let sender = tx_context::sender(ctx); assert!(sender == wallet.owner,0);
       // Check if wallet has enough balance    
       assert!(balance::value(&wallet.balance) >= amount, 1);
       // Create a coin with the specified amount    
       let transfer_coin = coin::take(&mut wallet.balance, amount, ctx)
       // Transfer the coin to the recipient    
       transfer::public_transfer(transfer.coin, recipient);
   }
}

