%builtins output pedersen range_check ecdsa
from starkware.cairo.common.dict import dict_read, dict_write, dict_update, dict_new, dict_squash
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.small_merkle_tree import (
    small_merkle_tree_update,
)



# The maximum amount of each token that belongs to the AMM.
const MAX_BALANCE = 2 ** 64 - 1

# Now we can compute the Merkle roots (we have arbitrarily chosen to use height of 10 in the Merkle tree,
#  supporting 2^10 = 1024 accounts):
const LOG_N_ACCOUNTS = 10


# Each account will contain the balances of the two tokens, and the public key of the user.
# Since this tutorial does not implement signature verification, we won’t really use the public_key field.
struct Account:
    member public_key : felt
    member token_a_balance : felt
    member token_b_balance : felt
end

struct AmmState:
    # A dictionary that tracks the accounts' state.
    member account_dict_start : DictAccess*
    member account_dict_end : DictAccess*
    # The amount of the tokens currently in the AMM.
    # Must be in the range [0, MAX_BALANCE].
    member token_a_balance : felt
    member token_b_balance : felt
end

# Represents a swap transaction between a user and the AMM.
struct SwapTransaction:
    member account_id : felt
    member token_a_amount : felt
end

func modify_account{range_check_ptr}(state : AmmState, account_id, diff_a, diff_b) -> (state : AmmState, key : felt):
    alloc_locals
    # Define a reference to state.account_dict_end so that we
    # can use it as an implicit argument to the dict
    let account_dict_end = state.account_dict_end

    # Retrieve the pointer to the current state of the account. --> the value (new_value) of the dict is 
    # actually the point to instance of Account struct. 
    let (local old_account : Account*) = dict_read{dict_ptr=account_dict_end}(key=account_id)
    # Compute the new account balances of both tokens.
    tempvar token_a_new_balance = (old_account.token_a_balance + diff_a)
    tempvar token_b_new_balance = (old_account.token_b_balance + diff_b)

    # Verify that the new balances are positive.
    assert_nn_le(token_a_new_balance, MAX_BALANCE)
    assert_nn_le(token_b_new_balance, MAX_BALANCE)

    # Create a new Account instance.
    local new_account : Account
    assert new_account.public_key = old_account.public_key
    assert new_account.token_a_balance = token_a_new_balance
    assert new_account.token_b_balance = token_b_new_balance

    # Perform the account update.
    # Note that dict_write() will update the 'account_dict_end' reference.
    let (__fp__, _) = get_fp_and_pc()

    dict_write{dict_ptr=account_dict_end}(key=account_id, new_value=cast(&new_account, felt))
    # Note that when we call dict_write() we need to cast the type of the value 
    # from Account* to felt: &new_account is of type Account*, 
    # but new_value expects a value of type felt.

    # Construct and return the new state with the updated 'account_dict_end'.
    local new_amm_state : AmmState
    assert new_amm_state.account_dict_start = state.account_dict_start
    assert new_amm_state.account_dict_end = account_dict_end
    assert new_amm_state.token_a_balance = token_a_new_balance
    assert new_amm_state.token_a_balance = token_b_new_balance 

    return (state=new_amm_state, key=old_account.public_key)

end

func swap{range_check_ptr}(state : AmmState, transaction : SwapTransaction*)-> (state : AmmState):
    alloc_locals

    # The amount to user will to swap for --> token_b
    tempvar a = transaction.token_a_amount
    # current balance of token_a
    tempvar x = state.token_a_balance
    # current balance of token_b
    tempvar y = state.token_b_balance

    # Check that a is in range.
    assert_nn_le(a, MAX_BALANCE)

    # Compute the amount of token_b the user will get:
    #   b = (a * y) / (x + a).
    let (b, _) = unsigned_div_rem(a * y, x + a)
    # Make sure that b is also in range
    assert_nn_le(b, MAX_BALANCE)

    # Update the user's account.
    let (state, key) = modify_account(
        state=state,
        account_id=transaction.account_id,
        diff_a=-a, # diduct amount of a from the balance of token_a of user account
        diff_b=b, # add token b in the balance of token_b of user account
    )

    # TODO
    # Here you should verify the user has signed on a message
    # specifying that they would like to sell 'a' tokens of
    # type token_a. You should use the public key returned by
    # modify_account().

    # Compute the new balances of the AMM *** and *** make sure they are in range.
    # New balance of token_a
    tempvar new_x = x + a
    # New balance of token_b
    tempvar new_y = y - b
    assert_nn_le(new_x, MAX_BALANCE)
    assert_nn_le(new_y, MAX_BALANCE)

    # Update the state.
    let new_state : AmmState
    assert new_state.account_dict_start = state.account_dict_start
    assert new_state.account_dict_end = state.account_dict_end
    assert new_state.token_a_balance = new_x
    assert new_state.token_b_balance = new_y

    %{
        # Print the transaction values using a hint, for
        # debugging purposes.
        print(
            f'Swap: Account {ids.transaction.account_id} '
            f'gave {ids.a} tokens of type token_a and '
            f'received {ids.b} tokens of type token_b.')
    %}

    return(state=new_state)
end

# The following function takes an array of transactions and applies them to the state:
# The type SwapTransaction** represents a pointer to a pointer to an instance of SwapTransaction.
func transaction_loop{range_check_ptr}(state : AmmState, transactions : SwapTransaction**, n_transactions
)-> (state : AmmState):
    if n_transactions == 0:
        return(state=state)
    end

    let first_transaction : SwapTransaction* = [transactions]
    # [transactions] is a pointer to the first transaction, [transactions + 1] is a pointer to the second transaction and so on.
    let (state) = swap(state=state, transaction=first_transaction)

    # Recursively call transaction_loop() method
    return transaction_loop(state=state, transaction=transactions + 1, n_transactions=n_transactions - 1)
end

# Returns a hash committing to the account's state using the
# following formula:
#   H(H(public_key, token_a_balance), token_b_balance).
# where H is the Pedersen hash function.
func hash_account{pedersen_ptr : HashBuiltin*}(account : Account*)-> (res : felt):
    let res = account.public_key
    H(public_key, token_a_balance)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, account.token_a_balance)
    # H(H(public_key, token_a_balance), token_b_balance)
    let (res) = hash2{hash_ptr=pedersen_ptr}(res, account.token_b_balance)

    return (res=res)
end

# For each entry in the input dict (represented by dict_start
# and dict_end) write an entry to the output dict (represented by
# hash_dict_start and hash_dict_end) after applying hash_account
# on prev_value and new_value and keeping the same key.
func hash_dict_values{pedersen_ptr : HashBuiltin*}(dict_start : DictAccess*, dict_end : DictAccess*, hash_dict_start : DictAccess*,
)-> (hash_dict_end : DictAccess*):

    if dict_start == dict_end:
        return(hash_dict_end=hash_dict_start)
    end
    
    # Compute the hash of the account before and after the change.
    # H --> Before change
    let (pre_hash) = hash_account(account=cast(dict_start.prev_value, Account*)
    # H --> After change
    let (new_hash) = hash_account(account=cast(dict_start.new_value, Account*)

    # Add an entry to the output dict.
    dict_update{dict_ptr=hash_dict_start}(
        key=dict_start.key, 
        prev_value=pre_hash, 
        new_value=new_hash
    )

    return hash_dict_values(
        dict_start=dict_start + DictAccess.SIZE,
        dict_end=dict_end + DictAccess.SIZE,
        hash_dict_start=hash_dict_start
    )
end

# Computes the Merkle roots before and after the batch.
# Hint argument: initial_account_dict should be a dictionary
# from account_id to an address in memory of the Account struct.
func compute_merkle_roots{pedersen_ptr : HashBuiltin*, range_check_ptr}(
    state : AmmState
)-> (root_before : felt, root_after : felt):
    alloc_locals

    # Squash the account dictionary.
    let(squashed_dict_start, squashed_dict_end) = dict_squash(
        dict_accesses_start=state.account_dict_start,
        dict_accesses_end=state.account_dict_end
    )

    # Hash the dict values.
    %{
        from starkware.crypto.signature.signature import pedersen_hash
        
        initial_dict = {}
        for account_id, account in initial_account_dict.items():
            public_key = memory[account + ids.Account.public_key]
            token_a_balance = memory[account + ids.Account.token_a_balance]
            token_b_balance = memory[account + ids.Account.token_b_balance]
                                                    #  H(H(public_key, token_a_balance), token_b_balance).
            initial_dict[account_id] = pedersen_hash(pedersen_hash(public_key, token_a_balance), token_b_balance)

    %}

    let (local hash_dict_start : DictAccess*) = new_dict()
    




