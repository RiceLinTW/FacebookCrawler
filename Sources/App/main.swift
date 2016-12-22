import Vapor
import Jobs

enum PostType {
    case post
    case photo
    case video
}

let drop = Droplet()

let graphAPIBase = (drop.config["facebook"]?.object?["graphAPIBase"]?.string)!
let clientID = (drop.config["facebook"]?.object?["clientId"]?.string)!
let clientSecret = (drop.config["facebook"]?.object?["clientSecret"]?.string)!
let pageId = (drop.config["facebook"]?.object?["pageId"]?.string)!
let fetchingInterval = (drop.config["facebook"]?.object?["fetchingInterval"]?.double)!

func startCrawling(type: [PostType], fields: String, complete: ([[String:Polymorphic]]) -> Void) {
    
    do {
        let tokenResponse = try drop.client.get(graphAPIBase + "oauth/access_token", headers: [
            "Accept":"application/json"
            ], query: [
                "client_id": clientID,
                "client_secret": clientSecret,
                "grant_type": "client_credentials"
            ])
        guard let token = tokenResponse.json?["access_token"]?.string else {
            print("something went wrong while getting token")
            throw Abort.custom(status: .unauthorized, message: "Token was not returned")}
        print("Start get posts")
        if type.count > 0 {
            var finalResult : [[String:Polymorphic]] = []
            if type.contains(.post) {
                let postResults = try getPosts(urlStr: graphAPIBase + pageId + "/posts", token: token, fields: fields)
                finalResult.append(contentsOf: postResults)
            }
            if type.contains(.photo) {
                let photoResults = try getAlbums(urlStr: graphAPIBase + pageId + "/albums", token: token, fields: fields)
                finalResult.append(contentsOf: photoResults)
            }
            if type.contains(.video) {
                let videoResults = try getVideos(urlStr: graphAPIBase + pageId + "/videos", token: token, fields: fields)
                finalResult.append(contentsOf: videoResults)
            }
            complete(finalResult)
        } else {
            print("Please choose one post type at least")
            return
        }
    } catch {
        print("something went wrong", error)
    }
}
func getPosts(urlStr: String, token: String, fields: String) throws -> [[String:Polymorphic]] {
    var result: [[String:Polymorphic]] = []
    let postResponse = try drop.client.get(urlStr, headers:[
        "Accept":"application/json"
        ], query: [
            "access_token": token,
            "limit": 100,
            "fields": fields
        ])
    guard let posts = postResponse.json!["data"]?.array?.map( { $0.object! } ) else {
        print("no data")
        return []
    }
    result.append(contentsOf: posts)

    if let next = postResponse.json!["paging"]?.object?["next"]?.string {
        do {
            let nextResults = try getPosts(urlStr: next.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!, token: token, fields: fields)
            result.append(contentsOf: nextResults)
        } catch {
            print("something went wrong", error)
        }
    }
    
    return result
}
func getAlbums(urlStr: String, token: String, fields: String) throws -> [[String:Polymorphic]] {
    var result: [[String:Polymorphic]] = []
    let albumResponse = try drop.client.get(urlStr, headers:[
        "Accept":"application/json"
        ], query: [
            "access_token": token,
            "limit": 50,
            "fields": "photos{id}"
        ])
    guard let albums = albumResponse.json!["data"]?.array else {
        print("no album")
        return []
    }
    for album in albums {
        if let photos = album.object?["photos"]?.object?["data"]?.array {
            let photoIds = photos.map( { $0.object?["id"]?.string } )
            for id in photoIds {
                let photoIdUrl = graphAPIBase + pageId + "_" + id!
                let photoResponse = try drop.client.get(photoIdUrl, headers:[
                    "Accept":"application/json"
                    ], query: [
                        "access_token": token,
                        "fields": fields
                    ])
                
                let photoObject = photoResponse.json?.makeNode().object
                result.append(photoObject!)

            }
        } else {
            print("no photo in this album")
        }
    }
    
    if let next = albumResponse.json!["paging"]?.object?["next"]?.string {
        do {
            let nextResults = try getAlbums(urlStr: next.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!, token: token, fields: fields)
            result.append(contentsOf: nextResults)
        } catch {
            print("something went wrong", error)
        }
    }
    
    return result
}
func getVideos(urlStr: String, token: String, fields: String) throws -> [[String:Polymorphic]] {
    var result: [[String:Polymorphic]] = []
    let videosResponse = try drop.client.get(urlStr, headers:[
        "Accept":"application/json"
        ], query: [
            "access_token": token,
            "limit": 50,
            "fields": "id"
        ])
    guard let videoIds = videosResponse.json!["data"]?.array?.map( { $0.object?["id"]?.string } ) else {
        print("no videos")
        return []
    }
    for id in videoIds {
        let videoIdUrl = graphAPIBase + pageId + "_" + id!
        let videoResponse = try drop.client.get(videoIdUrl, headers:[
            "Accept":"application/json"
            ], query: [
                "access_token": token,
                "fields": fields
            ])
        let videoObject = videoResponse.json?.makeNode().object
        result.append(videoObject!)
    }
        
    if let next = videosResponse.json!["paging"]?.object?["next"]?.string {
        do {
            let nextResults = try getVideos(urlStr: next.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!, token: token, fields: fields)
            result.append(contentsOf: nextResults)
        } catch {
            print("something went wrong", error)
        }
    }
    return result
}

Jobs.add(interval: .seconds(fetchingInterval), action: {
    // see graph API document: https://developers.facebook.com/docs/graph-api
    let fields = "id,created_time,message"
    
    startCrawling(type: [.post, .photo, .video], fields: fields, complete: { (posts) in
        // handling post objects
    })
})

drop.run()
