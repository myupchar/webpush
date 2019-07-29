# frozen_string_literal: true

module Webpush
  module Encryption
    extend self

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def encrypt(message, p256dh, auth)
      assert_arguments(message, p256dh, auth)

      group_name = 'prime256v1'
      salt = Random.new.bytes(16)

      server = OpenSSL::PKey::EC.new(group_name)
      server.generate_key
      server_public_key_bn = server.public_key.to_bn

      group = OpenSSL::PKey::EC::Group.new(group_name)
      client_public_key_bn = OpenSSL::BN.new(Webpush.decode64(p256dh), 2)
      client_public_key = OpenSSL::PKey::EC::Point.new(group, client_public_key_bn)

      shared_secret = server.dh_compute_key(client_public_key)

      client_auth_token = Webpush.decode64(auth)

      info =  "WebPush: info\0" + convert16bit(client_public_key_bn) + convert16bit(server_public_key_bn)
      keyinfo = "Content-Encoding: aes128gcm\0"
      nonce_info = "Content-Encoding: nonce\0"

      prk = HKDF.new(shared_secret, salt: client_auth_token, algorithm: 'SHA256', info: info).next_bytes(32)

      content_encryption_key = HKDF.new(prk, salt: salt, info: keyinfo).next_bytes(16)
      nonce = HKDF.new(prk, salt: salt, info: nonce_info).next_bytes(12)

      ciphertext = encrypt_payload(message, content_encryption_key, nonce)

      {
          ciphertext: ciphertext,
          salt: salt,
          server_public_key_bn: convert16bit(server_public_key_bn),
          server_public_key: server_public_key_bn.to_s(2),
          shared_secret: shared_secret
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def encrypt_payload(plaintext, content_encryption_key, nonce)
      cipher = OpenSSL::Cipher.new('aes-128-gcm')
      cipher.encrypt
      cipher.key = content_encryption_key
      cipher.iv = nonce

      text = cipher.update(plaintext)
      padding = cipher.update("\2\0")
      e_text = text + padding + cipher.final

      e_tag = cipher.auth_tag

      e_text + e_tag
    end

    def create_info(type, context)
      info = 'Content-Encoding: '
      info += type
      info += "\0"
      info += 'P-256'
      info += context
      info
    end

    def convert16bit(key)
      [key.to_s(16)].pack('H*')
    end

    def assert_arguments(message, p256dh, auth)
      raise ArgumentError, 'message cannot be blank' if blank?(message)
      raise ArgumentError, 'p256dh cannot be blank' if blank?(p256dh)
      raise ArgumentError, 'auth cannot be blank' if blank?(auth)
    end

    def blank?(value)
      value.nil? || value.empty?
    end
  end
end