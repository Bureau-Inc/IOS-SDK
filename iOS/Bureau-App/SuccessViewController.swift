//
//  SuccessViewController.swift
//  SilentAuthCheck
//
//  Created by Kurian Ninan K on 05/10/20.
//  Copyright © 2020 Keyvalue. All rights reserved.
//

import UIKit

class SuccessViewController: UIViewController {

    var mobileNumber: String?
    @IBOutlet weak var labelMobileNumber: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let mobileValue = mobileNumber{
            labelMobileNumber.text = mobileValue
        }
        // Do any additional setup after loading the view.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
