module simplewallet::wallet; 
   use sui::coin::{Self,Coin};
   use sui::sui::SUI;
   use sui::balance::{Self,Balance};

   public struct Wallet has key, store {
     id: UID,
     balance: Balance<SUI>,
     owner: address 
    }

   public entry fun create_wallet(ctx: &mut TxContext) { 
      let sender = tx_context::sender(ctx);
      let wallet = Wallet {
       id: object::new(ctx),
       balance: balance:: zero<SUI>(),
       owner: sender
      }; 
 
   transfer::transfer(wallet,sender);
   }

   public entry fun deposit(wallet: &mut Wallet, coin:Coin<SUI>, _ctx: &mut TxContext) {
      let coin_balance = coin::into_balance(coin);
      balance::join(&mut wallet.balance, coin_balance);
   }
 
   public entry fun transfer_to(wallet: &mut Wallet, amount: u64, recipient: address, ctx: &mut TxContext) {
       
       let sender = tx_context::sender(ctx); assert!(sender == wallet.owner,0);
       
       assert!(balance::value(&wallet.balance) >= amount, 1);
        
       let transfer_coin = coin::take(&mut wallet.balance, amount, ctx);
        
       transfer::public_transfer(transfer_coin, recipient);
}

   public entry fun withdraw(wallet: &mut Wallet, amount: u64, ctx: &mut TxContext) {
       let sender = tx_context::sender(ctx); assert!(sender == wallet.owner,0);
       
       assert!(balance::value(&wallet.balance) >= amount, 1);
        
       let transfer_coin = coin::take(&mut wallet.balance, amount, ctx);
        
       transfer::public_transfer(transfer_coin, sender);
}
