use aes_gcm::{
    aead::{AeadInPlace, KeyInit},
    Aes256Gcm, Nonce, Tag,
};

#[path = "key.rs"]
mod key;

const MAGIC: &[u8; 4] = b"NSCR";
const VERSION: u8 = 1;
const HEADER_LEN: usize = 4 + 1 + 12 + 16;

pub fn decrypt(encrypted: &[u8]) -> Result<Vec<u8>, String> {
    if encrypted.len() < HEADER_LEN {
        return Err("encrypted resource is shorter than the NSCR header".into());
    }
    if &encrypted[0..4] != MAGIC {
        return Err("invalid encrypted resource magic".into());
    }
    if encrypted[4] != VERSION {
        return Err(format!("unsupported encrypted resource version: {}", encrypted[4]));
    }

    let nonce = Nonce::from_slice(&encrypted[5..17]);
    let tag = Tag::from_slice(&encrypted[17..33]);
    let ciphertext = &encrypted[33..];

    let cipher = Aes256Gcm::new_from_slice(&key::key_bytes())
        .map_err(|_| "invalid AES-256 key".to_string())?;
    let mut plaintext = ciphertext.to_vec();
    cipher.decrypt_in_place_detached(nonce, b"", &mut plaintext, tag)
        .map_err(|_| "resource authentication/decryption failed".to_string())?;
    Ok(plaintext)
}
