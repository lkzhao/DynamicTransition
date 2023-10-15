//
//  File.swift
//  
//
//  Created by Luke Zhao on 10/14/23.
//

import Motion

extension SupportedSIMD where Scalar: SupportedScalar {
    func distance(between: Self) -> Scalar {
        var result = Scalar.zero
        for i in 0..<scalarCount {
            result += abs(self[i] - between[i])
        }
        return result
    }
}

extension SIMDRepresentable where SIMDType.Scalar: SupportedScalar {
    func distance(between other: Self) -> SIMDType.Scalar {
        simdRepresentation().distance(between: other.simdRepresentation())
    }
}
