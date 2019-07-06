//
//  DataTaskPublisherTests.swift
//  UsingCombineTests
//
//  Created by Joseph Heck on 7/5/19.
//  Copyright © 2019 SwiftUI-Notes. All rights reserved.
//

import XCTest
import Combine

class DataTaskPublisherTests: XCTestCase {

    var testURL: URL?
    var myBackgroundQueue: DispatchQueue?

    enum testFailureCondition: Error {
        case invalidServerResponse
    }

    let testUrlString = "https://postman-echo.com/time/valid?timestamp=2016-10-10"
    // checks the validity of a timestamp - this one should return {"valid":true}
    // matching the data structure returned from https://postman-echo.com/time/valid
    fileprivate struct PostmanEchoTimeStampCheckResponse: Decodable, Hashable {
        let valid: Bool
    }

    override func setUp() {
        self.testURL = URL(string: testUrlString)
        self.myBackgroundQueue = DispatchQueue(label: "UsingCombineExample", attributes: .concurrent)
    }

    func testDataTaskPublisher() {
        // setup
        let expectation = XCTestExpectation(description: "Download from \(String(describing: testURL))")
        let remoteDataPublisher = URLSession.shared.dataTaskPublisher(for: self.testURL!)
            // validate
            .sink(receiveCompletion: { fini in
                print(".sink() received the completion", String(describing: fini))
                switch fini {
                case .finished: expectation.fulfill()
                case .failure: XCTFail()
                }
            }, receiveValue: { (data, response) in
                guard let httpResponse = response as? HTTPURLResponse else {
                    XCTFail("Unable to parse response an HTTPURLResponse")
                    return
                }
                XCTAssertNotNil(data)
                // print(".sink() data received \(data)")
                XCTAssertNotNil(httpResponse)
                XCTAssertEqual(httpResponse.statusCode, 200)
                // print(".sink() httpResponse received \(httpResponse)")
            })

        XCTAssertNotNil(remoteDataPublisher)
        wait(for: [expectation], timeout: 5.0)
    }

    func testSimpleURLDecodePipeline() {
        // setup
        let expectation = XCTestExpectation(description: "Download from \(String(describing: testURL))")
        let remoteDataPublisher = URLSession.shared.dataTaskPublisher(for: self.testURL!)
            // the dataTaskPublisher output combination is (data: Data, response: URLResponse)
            .map { $0.data }
            .decode(type: PostmanEchoTimeStampCheckResponse.self, decoder: JSONDecoder())
            .subscribe(on: self.myBackgroundQueue!)
            .eraseToAnyPublisher()

        XCTAssertNotNil(remoteDataPublisher)

        // validate
        let _ = remoteDataPublisher
            .sink(receiveCompletion: { completion in
                print(".sink() received the completion", String(describing: completion))
                switch completion {
                case .finished: expectation.fulfill()
                case .failure: XCTFail()
                }
            }, receiveValue: { someValue in
                XCTAssertNotNil(someValue)
                print(".sink() received \(someValue)")
            })

        wait(for: [expectation], timeout: 5.0)
    }

    func testSimpleFailingURLDecodePipeline_URLError() {
        // setup
        let myURL = URL(string: "https://doesntexist.jsontest.com") // whole chain fails with completion/error sent from dataTaskPublisher
        let expectation = XCTestExpectation(description: "Download from \(String(describing: myURL))")
        let remoteDataPublisher = URLSession.shared.dataTaskPublisher(for: myURL!)
            // the dataTaskPublisher output combination is (data: Data, response: URLResponse)
            .map { $0.data }
            .decode(type: PostmanEchoTimeStampCheckResponse.self, decoder: JSONDecoder())
            .subscribe(on: self.myBackgroundQueue!)
            .eraseToAnyPublisher()

            // validate
            .sink(receiveCompletion: { fini in
                print(".sink() received the completion", String(describing: fini))
                switch fini {
                case .finished: XCTFail()
                case .failure(let anError):
                    print("received error: ", anError)
                    // URL doesn't exist, so a failure should be triggered
                    XCTAssertEqual(anError.localizedDescription, "A server with the specified hostname could not be found.")
                    expectation.fulfill()
                }
            }, receiveValue: { someValue in
//                XCTAssertNotNil(someValue)
                XCTFail("Should not have received a value with the failed URL")
                print(".sink() received \(someValue)")
            })

        XCTAssertNotNil(remoteDataPublisher)
        wait(for: [expectation], timeout: 5.0)
    }

    func testDataTaskPublisherWithTryMap() {
        // setup
        let expectation = XCTestExpectation(description: "Download from \(String(describing: testURL))")
        let remoteDataPublisher = URLSession.shared.dataTaskPublisher(for: self.testURL!)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200 else {
                        throw testFailureCondition.invalidServerResponse
                }
                return data
            }
            .decode(type: PostmanEchoTimeStampCheckResponse.self, decoder: JSONDecoder())
            .subscribe(on: self.myBackgroundQueue!)
            .eraseToAnyPublisher()

            // validate
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished: expectation.fulfill()
                case .failure(let anError):
                    XCTFail(anError.localizedDescription)
                }
            }, receiveValue: { decodedResponse in
                XCTAssertNotNil(decodedResponse)
                XCTAssertTrue(decodedResponse.valid)
            })

        XCTAssertNotNil(remoteDataPublisher)
        wait(for: [expectation], timeout: 5.0)
    }
}
