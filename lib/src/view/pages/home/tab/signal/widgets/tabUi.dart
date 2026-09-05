// import 'package:flutter/material.dart';
// class TabUi extends StatefulWidget {
//   @override
//   _TabUiState createState() => _TabUiState();
// }
// class _TabUiState extends State<TabUi> {
//   @override
//   Widget build(BuildContext context) {
//     return  Container(
//       decoration: BoxDecoration(
//         color: AppColors.cardGrey,
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: Padding(
//         padding: EdgeInsets.all(5),
//         child: Row(
//           children: [
//             Expanded(
//               child: GestureDetector(
//                 onTap: () {
//                   setState(() {
//                     _firstSelectedTabIndex = 0; // Signal Strength
//                   });
//                 },
//                 child: Container(
//                   padding: EdgeInsets.symmetric(vertical: 12),
//                   decoration: _firstSelectedTabIndex == 0
//                       ? BoxDecoration(
//                           color: AppColors.backgroundColor,
//                           borderRadius: BorderRadius.circular(8),
//                         )
//                       : null,
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(
//                         Icons.map,
//                         color: _firstSelectedTabIndex == 0
//                             ? AppColors.lightBlue
//                             : AppColors.white54,
//                         size: 20,
//                       ),
//                       SizedBox(width: 8),
//                       KText(
//                         text: 'Signal Strength',
//                         color: _firstSelectedTabIndex == 0
//                             ? AppColors.lightBlue
//                             : AppColors.white54,
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//             Expanded(
//               child: GestureDetector(
//                 onTap: () {
//                   setState(() {
//                     _firstSelectedTabIndex = 1; // Floor Plan
//                   });
//                 },
//                 child: Container(
//                   padding: EdgeInsets.symmetric(vertical: 12),
//                   decoration: _firstSelectedTabIndex == 1
//                       ? BoxDecoration(
//                           color: AppColors.backgroundColor,
//                           borderRadius: BorderRadius.circular(8),
//                         )
//                       : null,
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(
//                         Icons.map,
//                         color: _firstSelectedTabIndex == 1
//                             ? AppColors.lightBlue
//                             : AppColors.white54,
//                         size: 20,
//                       ),
//                       SizedBox(width: 8),
//                       KText(
//                         text: 'Floor Plan',
//                         color: _firstSelectedTabIndex == 1
//                             ? AppColors.lightBlue
//                             : AppColors.white54,
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// } 