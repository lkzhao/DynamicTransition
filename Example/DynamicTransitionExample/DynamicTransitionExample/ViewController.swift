//
//  ViewController.swift
//  DynamicTransitionExample
//
//  Created by Luke Zhao on 11/11/23.
//

import UIKit
import DynamicTransition

class HomeView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .red
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
    }

    @objc func didTap() {
        navigationController?.pushView(DetailView(), animated: true)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



class DetailView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .green
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
    }

    @objc func didTap() {
        navigationController?.popView(animated: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

