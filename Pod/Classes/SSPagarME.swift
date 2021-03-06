//
//  SSPagarME.swift
//
//  Created by Rodrigo Priolo on 29/09/16.
//  Copyright © 2016 Rodrigo Priolo < smartside.com.br >. All rights reserved.
//

import Foundation
import SwiftyRSA

public typealias SuccessCardHash = (_ card_hash: String) -> Void
public typealias FailureCardHash = (_ message: String) -> Void

public typealias SuccessTransaction = (_ data: [String: Any]) -> Void
public typealias FailureTransaction = (_ message: String) -> Void

public struct Card {
    public var cardNumber: String?
    public var cardHolderName: String?
    public var cardExpirationMonth: String?
    public var cardExpirationYear: String?
    public var cardCVV: String?
    
    internal func cardHash() -> String {
        return String(format: "card_number=%@&card_holder_name=%@&card_expiration_date=%@%@&card_cvv=%@",
                      cardNumber!, cardHolderName!, cardExpirationMonth!, cardExpirationYear!, cardCVV!)
    }
    
    internal func check() -> String? {
        if let cn = self.cardNumber {
            if luhnAlgorithm(cardNumber: cn) == false {
                return "Número de cartão inválido"
            }
        } else {
            return "Verifique o número do cartão"
        }
        
        if self.cardHolderName == nil || (self.cardHolderName?.count)! <= 0 {
            return "Verifique o nome do cartão"
        }
        
        if self.cardExpirationMonth == nil || (self.cardExpirationMonth?.count)! < 2 || (Int(self.cardExpirationMonth!)! <= 0 || Int(self.cardExpirationMonth!)! > 12) {
            return "Verifique o mês de expiração do cartão"
        }
        
        if self.cardExpirationYear == nil || (self.cardExpirationYear?.count)! < 2 || (Int(self.cardExpirationYear!)! <= 0 || Int(self.cardExpirationYear!)! > 99) {
            return "Verifique o ano de expiração do cartão"
        }
        
        if self.cardCVV == nil || self.cardCVV?.count != 3 {
            return "Verifique o o código de segurança(CVV) do cartão"
        }
        
        return nil
    }
    
    func luhnAlgorithm(cardNumber: String) -> Bool{
        var luhn_sum = 0
        var digit_count = 0
        //reverse the card
        for c in cardNumber.reversed() {
            //count digits
            //print(c.self)
            let this_digit = Int(String(c as Character))!
            //print(this_digit)
            digit_count += 1
            //double every even digit
            if digit_count % 2 == 0{
                if this_digit * 2 > 9 {
                    luhn_sum = luhn_sum + this_digit * 2 - 9
                }else{
                    luhn_sum = luhn_sum + this_digit * 2
                }
            }else{
                luhn_sum = luhn_sum + this_digit
            }
            
        }
        if luhn_sum % 10 == 0{
            return true
        }
        return false
    }
}

public struct Customer {
    public var name: String? = nil
    public var document_number: String? = nil
    public var email: String? = nil
    public var street: String? = nil
    public var neighborhood: String? = nil
    public var zipcode: String? = nil
    public var street_number: String? = nil
    public var complementary: String? = nil
    public var ddd: String? = nil
    public var number: String? = nil
    
    public init () { }
    
    public func data() -> [String: Any] {
        var customer = [String: Any]()
        
        customer["name"] = name
        customer["document_number"] = document_number
        customer["email"] = email
        
        var address = [String: Any]()
        address["street"] = street
        address["neighborhood"] = neighborhood
        address["zipcode"] = zipcode
        address["street_number"] = street_number
        address["complementary"] = complementary
        customer["address"] = address
        
        var phone = [String: Any]()
        phone["ddd"] = ddd
        phone["number"] = number
        customer["phone"] = phone
        
        return customer
    }
}

public class SSPagarME: NSObject {
    
    // API pagar.me
    static private let baseURL: String = "https://api.pagar.me/1"
    static private let transactions = "/transactions" // endPoint transaction
    static private let card_hash = transactions + "/card_hash_key?encryption_key=%@" // generate card_hash
    
    static private let API_KEY: String = "apiKey"
    static private let ENCRYPTION_KEY: String = "encryptionKey"
    
    public var card = Card()
    public var customer = Customer()
    
    // MARK: Singleton
    public class var sharedInstance: SSPagarME {
        
        struct Static {
            static let instance: SSPagarME = SSPagarME()
        }
        return Static.instance
    }
    
    // MARK: Public
    static public func storeKeys(apiKey: String, encryptionKey key: String) {
        let userDefaults = UserDefaults.standard
        userDefaults.setValue(apiKey, forKeyPath: API_KEY)
        userDefaults.setValue(key, forKeyPath: ENCRYPTION_KEY)
    }
    
    
    /// Public Method generator Card Hash with Pagar.me
    ///
    /// - parameter success: Return card hash code (String)
    /// - parameter failure: Return message Error (String)
    public func generateCardHash(success: @escaping SuccessCardHash, failure: @escaping FailureCardHash) {
        if let message = self.card.check() {
            failure(message)
            return
        }
        
        self.generateNewPublicKey(success: { (card_hash) in
            success(card_hash)
        }) { (message) in
            failure(message)
        }
        
        
        return
    }
    
    public func transaction(amount: String, success: @escaping SuccessTransaction, failure: @escaping FailureTransaction) {
        if let message = self.card.check() {
            failure(message)
            return
        }
        
        self.generateNewPublicKey(success: { (card_hash) in
            var params: [String: Any] = [String: Any]()
            params["api_key"] = self.apiKey()
            params["amount"] = amount
            params["card_hash"] = card_hash
            params["customer"] = self.customer.data()
            
            do {
                let url = NSURL(string: String(format: "%@%@", SSPagarME.baseURL, SSPagarME.transactions))
                let request = NSMutableURLRequest(url: url! as URL, cachePolicy: NSURLRequest.CachePolicy.reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: params, options: JSONSerialization.WritingOptions())
                
                let session = URLSession.shared
                let dataTask = session.dataTask(with: request as URLRequest) { (data, response, error) in
                    do {
                        let json = try JSONSerialization.jsonObject(with: data!, options: [])
                        if let jsonDict = json as? [String : Any]
                        {
                            //print("json: \(jsonDict)")
                            //print("err \(jsonDict["error"])")
                            
                            if let error = jsonDict["error"] {
                                failure(error as! String)
                            } else {
                                success(["transition": jsonDict])
                            }
                        }
                    } catch let err as NSError {
                        //print(err.localizedDescription)
                        failure(err.localizedDescription)
                    }
                }
                
                dataTask.resume()
            } catch let err as NSError {
                //print(err.localizedDescription)
                failure(err.localizedDescription)
            }
        }) { (message) in
            failure(message)
        }
    }
    
    // MARK: Private
    private func generateNewPublicKey(success: @escaping SuccessCardHash, failure: @escaping FailureCardHash) {
        let url = NSURL(string: String(format: "%@%@", SSPagarME.baseURL, String(format: SSPagarME.card_hash, self.encryptionKey())))
        let request = NSMutableURLRequest(url: url! as URL, cachePolicy: NSURLRequest.CachePolicy.reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        request.httpMethod = "GET"
        
        let session = URLSession.shared
        let dataTask = session.dataTask(with: request as URLRequest) { (data, response, error) in
            if let _ = error {
                //print("error \(error)")
                return;
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data!, options: [])
                if let jsonDict = json as? [String : Any]
                {
                    //print("json: \(jsonDict)")
                    //print("err: \(jsonDict["error"])")
                    
                    let _id = jsonDict["id"] as! Int
                    let publicKeyPEM = jsonDict["public_key"] as! String
                    
                    let clear = try ClearMessage(string: self.card.cardHash(), using: .utf8)
                    let publicKey = try PublicKey(pemEncoded: publicKeyPEM)
                    let encrypted = try clear.encrypted(with: publicKey, padding: .PKCS1)
                    let base64String = encrypted.base64String
                    
                    success(String(format: "%@_%@", String(_id), base64String))
                }
                
                
                if let jsonErr = json as? [String : Any]
                {
                    let err = jsonErr["error"]
                    if let _ = err {
                        print("err \(String(describing: err))")
                        failure(String(describing: err))
                    }
                }
                
                
            } catch let err as NSError {
                //print("Error: \(err.localizedDescription)")
                failure(err.localizedDescription)
            }
        }
        
        dataTask.resume()
    }
    
    // MARK: Helper
    private func apiKey() -> String {
        let userDefaults = UserDefaults.standard
        return userDefaults.value(forKey: SSPagarME.API_KEY) as! String
    }
    
    private func encryptionKey() -> String {
        let userDefaults = UserDefaults.standard
        return userDefaults.value(forKey: SSPagarME.ENCRYPTION_KEY) as! String
    }
}
