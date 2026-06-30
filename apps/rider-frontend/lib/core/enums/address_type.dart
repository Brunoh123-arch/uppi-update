import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';

enum AddressType {
  home,
  work,
  partner,
  gym,
  parent,
  cafe,
  park,
  other,
}

extension AddressTypeX on AddressType {
  String title(BuildContext context) {
    switch (this) {
      case AddressType.home:
        return context.translate.addressHome;
      case AddressType.work:
        return context.translate.addressWork;
      case AddressType.partner:
        return context.translate.addressPartner;
      case AddressType.gym:
        return context.translate.addressGym;
      case AddressType.parent:
        return context.translate.addressParent;
      case AddressType.cafe:
        return context.translate.addressCafe;
      case AddressType.park:
        return context.translate.addressPark;
      case AddressType.other:
        return context.translate.addressOther;
    }
  }

  IconData get icon {
    switch (this) {
      case AddressType.home:
        return Ionicons.home;
      case AddressType.work:
        return Ionicons.business;
      case AddressType.partner:
        return Ionicons.heart;
      case AddressType.gym:
        return Ionicons.fitness;
      case AddressType.parent:
        return Ionicons.people;
      case AddressType.cafe:
        return Ionicons.cafe;
      case AddressType.park:
        return Ionicons.leaf;
      case AddressType.other:
        return Ionicons.ellipsis_horizontal_circle;
    }
  }
}
