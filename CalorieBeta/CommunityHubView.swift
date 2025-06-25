import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CommunityHubView: View {
    @EnvironmentObject var groupService: GroupService
    @State private var posts: [CommunityPost] = []
    @State private var showingCreatePostView = false
    @State private var showingJoinConfirmation = false
    @State private var selectedGroup: CommunityGroup?
    @State private var groups: [CommunityGroup] = []
    @State private var isMemberOfSelectedGroup = false
    
    let presetGroups = [
        CommunityGroup(id: "1", name: "Health & Wellness", description: "Discuss health tips and wellness strategies", creatorID: "preset", isPreset: true),
        CommunityGroup(id: "2", name: "Recipes & Cooking", description: "Share your favorite recipes and cooking tips", creatorID: "preset", isPreset: true),
        CommunityGroup(id: "3", name: "Fitness", description: "Talk about workouts, fitness goals, and more", creatorID: "preset", isPreset: true)
    ]
    
    var body: some View {
        NavigationView {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    Text("Groups")
                        .font(.headline)
                        .padding([.top, .leading])
                    List(presetGroups) { group in
                        Button(action: {
                            selectedGroup = group
                            if let groupID = group.id {
                                checkGroupMembership(groupID: groupID)
                            }
                        }) {
                            Text(group.name)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                    }
                    .listStyle(PlainListStyle())
                    .frame(width: UIScreen.main.bounds.width * 0.2)
                    .background(Color(.systemGray6))
                }

                Divider()
                
                VStack {
                    if let group = selectedGroup, let groupID = group.id {
                        Text("Viewing posts in \(group.name)")
                            .font(.title2)
                            .padding()
                        
                        if isMemberOfSelectedGroup {
                            Button(action: { showingCreatePostView = true }) {
                                Text("Create Post")
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding()
                            .sheet(isPresented: $showingCreatePostView) {
                                CreatePostView(groupID: groupID) { newPost in
                                    savePostToFirebase(post: newPost)
                                }
                            }
                            
                            List(posts) { post in
                                PostRowView(post: post) // Assumes PostRowView is defined elsewhere
                                    .padding(.vertical, 4)
                            }
                        } else {
                            Button("Join \(group.name) Group") {
                                showingJoinConfirmation = true
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .alert(isPresented: $showingJoinConfirmation) {
                                Alert(
                                    title: Text("Join Group"),
                                    message: Text("Would you like to join \(group.name)?"),
                                    primaryButton: .default(Text("Join")) {
                                        joinGroup(groupID: groupID)
                                    },
                                    secondaryButton: .cancel()
                                )
                            }
                        }
                    } else {
                        Text("Select a group to view posts")
                            .font(.title2)
                            .padding()
                    }
                }
            }
        }
    }

    private func checkGroupMembership(groupID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let membershipID = "\(userID)_\(groupID)"
        Firestore.firestore().collection("groupMemberships").document(membershipID).getDocument { document, error in
            if let error = error {
                return
            }
            if document?.exists == true {
                isMemberOfSelectedGroup = true
                fetchPostsForGroup(groupID: groupID)
            } else {
                isMemberOfSelectedGroup = false
                self.posts = []
            }
        }
    }

    private func fetchPostsForGroup(groupID: String) {
        let db = Firestore.firestore()
        db.collection("posts")
            .whereField("groupID", isEqualTo: groupID)
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    return
                }
                guard let documents = snapshot?.documents else { return }
                self.posts = documents.compactMap { doc -> CommunityPost? in
                    try? doc.data(as: CommunityPost.self)
                }
            }
    }

    private func savePostToFirebase(post: CommunityPost) {
        let db = Firestore.firestore()
        guard let postId = post.id else {
            return
        }
        do {
            try db.collection("posts").document(postId).setData(from: post)
        } catch {
        }
    }

    private func joinGroup(groupID: String) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        groupService.joinGroup(userID: userID, groupID: groupID) { error in
            if let error = error {
            } else {
                isMemberOfSelectedGroup = true
                fetchPostsForGroup(groupID: groupID)
            }
        }
    }
}

// IMPORTANT:
// The definitions for 'PostRowView' and 'CommentsView' are NOT included below.
// Please ensure you have these structs defined in their own separate files
// (e.g., PostRowView.swift and CommentsView.swift) and that these files
// are correctly included in your app's target.
